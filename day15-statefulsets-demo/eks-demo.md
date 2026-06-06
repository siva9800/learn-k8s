# StatefulSet Demo on EKS - Production-Grade PostgreSQL

> **Goal:** Run a PostgreSQL StatefulSet on real **AWS EKS**, where each pod gets its **own EBS volume** and a stable identity - the realistic pattern for databases on Kubernetes.

> **Pre-requisite:** [Day 14 - StatefulSets Theory](../day14-statefulsets/notes.md) | [Day 15 - StatefulSets Demo (Local)](notes.md)
>
> **Cluster requirement:** EKS cluster with EBS CSI driver installed.
> See [EBS CSI Driver Setup](../day13-volumes-demo/eks-demo.md) for installation steps.

---

## Learning Objectives

By the end you will be able to:

- Deploy PostgreSQL as a StatefulSet with per-pod **EBS** volumes
- Wire up **two services** (headless + regular) and know when to use each
- Connect from another pod the way a real **microservice** would
- Prove **data persistence** across pod and StatefulSet deletion
- Scale safely and **clean up EBS** to avoid charges

---

## Real-World Analogy

Each "permanent employee" (`pg-0`, `pg-1`, `pg-2`) gets a **personal safe-deposit box at the bank** - a real **AWS EBS volume**. The catch: a box lives in **one bank branch (Availability Zone)**, so the employee must sit in the **same branch as their box**. That's exactly why we use `WaitForFirstConsumer` - it creates each box in the branch where its employee will sit.

The office also has **two phone numbers**:

- **Regular Service (`postgres-service`)** = the **front desk** - call it and you reach *any available* employee (load-balanced reads).
- **Headless Service (`postgres-headless`)** = each employee's **direct desk line** - `pg-0.postgres-headless` always reaches `pg-0` (e.g. the primary, for writes).

> **Heads-up on "replication":** This demo runs **3 independent PostgreSQL instances**, each with its own EBS volume. It demonstrates *identity + per-pod storage + the two-service pattern* - it does **not** configure streaming replication between them (that needs `primary_conninfo`, a replication user, and an init script, or an operator). The architecture diagrams below show where replication *would* flow in a fully wired setup.

---

## Architecture

```mermaid
flowchart TB
    App[" App / microservice<br/>(order-service)"]
    App -->|reads, load-balanced| RS[" postgres-service<br/>(ClusterIP)"]
    App -.writes, direct.-> H0[" pg-0.postgres-headless"]
    RS --> P0 & P1 & P2
    H0 --> P0
    subgraph STS["StatefulSet: pg (replicas 3)"]
      P0[" pg-0 (primary)"]
      P1[" pg-1 (replica)"]
      P2[" pg-2 (replica)"]
    end
    P0 --> E0[(" EBS gp3 20Gi<br/>postgres-data-pg-0 · AZ-a")]
    P1 --> E1[(" EBS gp3 20Gi<br/>postgres-data-pg-1 · AZ-b")]
    P2 --> E2[(" EBS gp3 20Gi<br/>postgres-data-pg-2 · AZ-c")]

    classDef pod fill:#dbeafe,stroke:#2563eb;
    classDef aws fill:#fff7ed,stroke:#ea580c;
    class P0,P1,P2 pod;
    class E0,E1,E2 aws;
```

---

## What We'll Build

```
Production PostgreSQL on EKS:

                    +-------------------+
                    |  Your App / API   |
                    |  (order-service)  |
                    +--------+----------+
                             |
              +--------------+--------------+
              |                             |
              v                             v
    +------------------+          +--------------------+
    | postgres-service |          | postgres-headless  |
    | (Regular - ClusterIP)       | (Headless)         |
    | For app connections|        | For replication     |
    | Load balanced     |         | Direct pod access   |
    +--------+---------+          +--------+-----------+
              |                             |
    +---------+---------+         +---------+---------+
    |         |         |         |         |         |
    v         v         v         v         v         v
  pg-0      pg-1      pg-2     pg-0      pg-1      pg-2
(Primary) (Replica) (Replica) (Primary) (Replica) (Replica)
    |         |         |
  EBS-0     EBS-1     EBS-2
 (own)     (own)      (own)
```

### What We'll Demo

```
Demo 1: Deploy PostgreSQL StatefulSet (production-grade)
Demo 2: Connect to PostgreSQL from another pod (like a real microservice)
Demo 3: Test data persistence (delete pod, data survives)
Demo 4: Test headless vs regular service (write to primary, read from any)
Demo 5: Scale and observe behavior
Clean up
```

---

## Setup: StorageClass for PostgreSQL

If you already created `ebs-gp3` StorageClass from the volumes demo, skip this step.

```yaml
# postgres-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Retain              # Retain for databases! Don't auto-delete data
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
kubectl apply -f postgres-storageclass.yaml
```

```
Why "Retain" for databases?
  - reclaimPolicy: Delete  --> PVC deleted = EBS volume GONE = data LOST
  - reclaimPolicy: Retain  --> PVC deleted = EBS volume STAYS in AWS = data SAFE

  For databases, ALWAYS use Retain. You don't want an accidental
  "kubectl delete pvc" to wipe your production database.
```

---

## Demo 1: Deploy PostgreSQL StatefulSet (Production-Grade)

### Step 1: Create namespace

```bash
kubectl create namespace database
```

### Step 2: Create Secret for PostgreSQL passwords

```yaml
# postgres-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: database
type: Opaque
stringData:
  POSTGRES_USER: admin
  POSTGRES_PASSWORD: SuperSecretPass123
  POSTGRES_DB: appdb
```

```bash
kubectl apply -f postgres-secret.yaml
```

```
In production, use:
  - AWS Secrets Manager with External Secrets Operator
  - Or Sealed Secrets
  - Never commit real passwords to git!
  - This is just for demo purposes.
```

### Step 3: Create the Headless Service (for StatefulSet + replication)

```yaml
# postgres-headless-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
  namespace: database
  labels:
    app: postgres
spec:
  clusterIP: None                    # <-- Headless!
  selector:
    app: postgres
  ports:
  - port: 5432
    name: postgres
```

### Step 4: Create Regular Service (for app connections)

```yaml
# postgres-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: database
  labels:
    app: postgres
spec:
  type: ClusterIP                    # <-- Regular service with virtual IP
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
    name: postgres
```

```bash
kubectl apply -f postgres-headless-service.yaml
kubectl apply -f postgres-service.yaml
```

```
Why TWO services?

Headless Service (postgres-headless):
  - clusterIP: None
  - Returns individual pod IPs
  - Used for: StatefulSet requirement, direct pod access
  - DNS: pg-0.postgres-headless.database.svc.cluster.local
  - Use case: Connect to PRIMARY specifically for writes
             Database replicas finding each other for replication

Regular Service (postgres-service):
  - clusterIP: auto-assigned (e.g., 10.100.45.23)
  - Load balances across all pods
  - Used for: App connections (reads)
  - DNS: postgres-service.database.svc.cluster.local
  - Use case: Your microservices connect here for read queries
```

### Step 5: Create the PostgreSQL StatefulSet

```yaml
# postgres-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: pg
  namespace: database
spec:
  serviceName: postgres-headless     # Must match headless service name
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - containerPort: 5432
          name: postgres

        # Environment variables from Secret
        envFrom:
        - secretRef:
            name: postgres-secret

        # Mount data directory
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
          subPath: pgdata                # Important! PostgreSQL needs a subdirectory

  # Each pod gets its OWN EBS volume
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-gp3          # Uses our gp3 StorageClass
      resources:
        requests:
          storage: 20Gi                  # 20GB per replica
```

```bash
kubectl apply -f postgres-statefulset.yaml
```

### Step 6: Watch pods come up in order

```bash
kubectl get pods -n database -w
# NAME   READY   STATUS              RESTARTS   AGE
# pg-0   0/1     ContainerCreating   0          2s
# pg-0   1/1     Running             0          15s     <-- pg-0 ready first
# pg-1   0/1     Pending             0          0s      <-- pg-1 starts now
# pg-1   1/1     Running             0          20s
# pg-2   0/1     Pending             0          0s      <-- pg-2 starts now
# pg-2   1/1     Running             0          18s
```

### Step 7: Verify everything

```bash
# Check pods
kubectl get pods -n database -o wide
# NAME   READY   STATUS    NODE          AGE
# pg-0   1/1     Running   ip-10-0-1-x   60s
# pg-1   1/1     Running   ip-10-0-2-x   40s
# pg-2   1/1     Running   ip-10-0-1-x   20s

# Check PVCs -- each pod has its own EBS volume
kubectl get pvc -n database
# NAME                STATUS   VOLUME          CAPACITY   STORAGECLASS   AGE
# postgres-data-pg-0  Bound    pvc-abc123...   20Gi       ebs-gp3        60s
# postgres-data-pg-1  Bound    pvc-def456...   20Gi       ebs-gp3        40s
# postgres-data-pg-2  Bound    pvc-ghi789...   20Gi       ebs-gp3        20s

# Check services
kubectl get svc -n database
# NAME                TYPE        CLUSTER-IP     PORT(S)    AGE
# postgres-headless   ClusterIP   None           5432/TCP   2m
# postgres-service    ClusterIP   10.100.45.23   5432/TCP   2m

# Verify PostgreSQL is running on pg-0
kubectl exec pg-0 -n database -- pg_isready -U admin -d appdb
# /var/run/postgresql:5432 - accepting connections
```

```
What happened behind the scenes:

1. pg-0 created --> K8s creates PVC postgres-data-pg-0
   --> EBS CSI driver creates 20GB gp3 EBS in same AZ as pg-0's node
   --> PostgreSQL starts, initializes database

2. pg-1 created --> K8s creates PVC postgres-data-pg-1
   --> Another 20GB EBS volume created
   --> PostgreSQL starts with fresh database

3. pg-2 created --> same process, third EBS volume

Total: 3 pods, 3 PVCs, 3 EBS volumes = 60GB EBS storage
```

---

## Demo 2: Connect to PostgreSQL from Another Pod

This simulates a real microservice connecting to the database.

### Method 1: Using a temporary client pod

```bash
# Launch a PostgreSQL client pod
kubectl run pg-client \
  --image=postgres:16 \
  --namespace=database \
  --rm -it \
  --env="PGPASSWORD=SuperSecretPass123" \
  -- bash
```

Inside the client pod:

```bash
# Connect using the REGULAR service (load balanced)
psql -h postgres-service -U admin -d appdb

# You're now connected! Create a table and insert data:
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    product VARCHAR(100) NOT NULL,
    quantity INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO orders (product, quantity) VALUES
    ('Laptop', 2),
    ('Phone', 5),
    ('Tablet', 1);

SELECT * FROM orders;
--  id | product | quantity |         created_at
-- ----+---------+----------+----------------------------
--   1 | Laptop  |        2 | 2026-03-01 10:30:00.123456
--   2 | Phone   |        5 | 2026-03-01 10:30:00.123456
--   3 | Tablet  |        1 | 2026-03-01 10:30:00.123456

-- Exit psql
\q

# Exit the client pod
exit
```

### Method 2: Connect directly to a specific pod (via headless service)

```bash
kubectl run pg-client \
  --image=postgres:16 \
  --namespace=database \
  --rm -it \
  --env="PGPASSWORD=SuperSecretPass123" \
  -- bash
```

Inside the client pod:

```bash
# Connect to pg-0 SPECIFICALLY using headless service DNS
psql -h pg-0.postgres-headless -U admin -d appdb

# Verify which pod we're on
SELECT inet_server_addr();
-- Returns the IP of pg-0

\q

# Connect to pg-1 SPECIFICALLY
psql -h pg-1.postgres-headless -U admin -d appdb

SELECT inet_server_addr();
-- Returns the IP of pg-1 (different!)

\q
exit
```

```
Connection Comparison:

Regular Service (postgres-service):
  psql -h postgres-service -U admin -d appdb
  --> connects to ANY pod (load balanced)
  --> good for: general queries from your app

Headless Service (postgres-headless):
  psql -h pg-0.postgres-headless -U admin -d appdb
  --> connects to pg-0 SPECIFICALLY
  --> good for: connecting to primary for writes,
                replicas connecting to primary for replication
```

### Method 3: How your microservice would connect (real production)

```yaml
# order-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: database
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-service
  template:
    metadata:
      labels:
        app: order-service
    spec:
      containers:
      - name: app
        image: postgres:16             # Using postgres image just to demo connection
        command: ["sleep", "infinity"]  # Keep pod running for testing
        env:
        # Connection string using the REGULAR service
        - name: DATABASE_URL
          value: "postgresql://admin:SuperSecretPass123@postgres-service.database.svc.cluster.local:5432/appdb"

        # OR using individual env vars (more common)
        - name: DB_HOST
          value: "postgres-service.database.svc.cluster.local"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "appdb"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
```

```bash
kubectl apply -f order-service.yaml

# Test connection from the microservice
kubectl exec -it $(kubectl get pod -l app=order-service -n database -o name | head -1) \
  -n database -- psql -h postgres-service -U admin -d appdb -c "SELECT * FROM orders;"
```

```
Production connection patterns:

Same namespace:
  DB_HOST = postgres-service          (short form)

Cross namespace (order-service in "app" namespace, postgres in "database" namespace):
  DB_HOST = postgres-service.database.svc.cluster.local  (full DNS)

                  +----- "app" namespace -----+
                  |                            |
                  | order-service              |
                  |   DB_HOST = postgres-      |
                  |   service.database.svc.    |
                  |   cluster.local            |
                  +------------+---------------+
                               |
                  +------------v---------------+
                  |                            |
                  | "database" namespace       |
                  |                            |
                  | postgres-service (ClusterIP)|
                  |       |                    |
                  |   pg-0  pg-1  pg-2         |
                  +----------------------------+
```

---

## Demo 3: Data Persistence Test

### Test 1: Delete a pod -- data survives

```bash
# First, verify data exists on pg-0
kubectl exec pg-0 -n database -- \
  psql -U admin -d appdb -c "SELECT * FROM orders;"

# Delete pg-0
kubectl delete pod pg-0 -n database

# Watch it come back
kubectl get pods -n database -w
# pg-0   1/1   Terminating   0   10m
# pg-0   0/1   Pending       0   0s       <-- Same name: pg-0
# pg-0   0/1   ContainerCreating   0   1s
# pg-0   1/1   Running       0   15s      <-- Back!

# Check data -- still there!
kubectl exec pg-0 -n database -- \
  psql -U admin -d appdb -c "SELECT * FROM orders;"
#  id | product | quantity | created_at
# ----+---------+----------+------------------
#   1 | Laptop  |        2 | ...
#   2 | Phone   |        5 | ...
#   3 | Tablet  |        1 | ...
```

```
What happened:
  1. pg-0 deleted --> EBS volume detached from old node
  2. New pg-0 created --> might be on same or different node (same AZ)
  3. EBS volume reattached to new node (~30-60 sec)
  4. PostgreSQL starts, finds existing data in /var/lib/postgresql/data
  5. All tables, rows, indexes are intact!
```

### Test 2: Delete the ENTIRE StatefulSet -- data survives

```bash
# Delete the StatefulSet
kubectl delete statefulset pg -n database

# Pods are gone
kubectl get pods -n database -l app=postgres
# No resources found

# But PVCs are still there!
kubectl get pvc -n database
# NAME                STATUS   VOLUME          CAPACITY   STORAGECLASS
# postgres-data-pg-0  Bound    pvc-abc123...   20Gi       ebs-gp3
# postgres-data-pg-1  Bound    pvc-def456...   20Gi       ebs-gp3
# postgres-data-pg-2  Bound    pvc-ghi789...   20Gi       ebs-gp3

# Recreate StatefulSet
kubectl apply -f postgres-statefulset.yaml

# Wait for pods
kubectl get pods -n database -w

# Data is STILL there!
kubectl exec pg-0 -n database -- \
  psql -U admin -d appdb -c "SELECT * FROM orders;"
# All 3 rows still exist!
```

```
Why data survives:

  StatefulSet deleted --> pods deleted --> EBS detached
  But PVCs are NOT deleted (by design)
  EBS volumes still exist in AWS

  StatefulSet recreated --> pg-0 created --> binds to PVC postgres-data-pg-0
  --> same EBS volume reattached --> PostgreSQL finds existing data
```

---

## Demo 4: Headless vs Regular Service (Production Use Case)

### Understanding both services with DNS

```bash
# Launch a DNS test pod
kubectl run dns-test --image=busybox:1.36 -n database --rm -it -- sh
```

Inside the pod:

```bash
# Regular service -- returns ONE virtual IP
nslookup postgres-service.database.svc.cluster.local
# Address: 10.100.45.23      <-- single ClusterIP (load balanced)

# Headless service -- returns ALL pod IPs
nslookup postgres-headless.database.svc.cluster.local
# Address: 10.244.0.15       <-- pg-0
# Address: 10.244.1.22       <-- pg-1
# Address: 10.244.2.18       <-- pg-2

# Specific pod DNS (only works with headless)
nslookup pg-0.postgres-headless.database.svc.cluster.local
# Address: 10.244.0.15       <-- always pg-0

nslookup pg-1.postgres-headless.database.svc.cluster.local
# Address: 10.244.1.22       <-- always pg-1

exit
```

### When to use which service

```
Your app code (order-service, user-service, etc.):

  # For READ queries (any replica is fine):
  DB_HOST = "postgres-service"
  --> load balanced, any pod can answer a SELECT

  # For WRITE queries (must go to primary):
  DB_HOST = "pg-0.postgres-headless"
  --> always reaches pg-0 (the primary)

  # In a real production setup with connection pooling (PgBouncer):
  DB_HOST = "pgbouncer-service"
  --> PgBouncer handles read/write splitting

PostgreSQL replication (internal, DB-to-DB):

  # pg-1 connects to pg-0 for replication:
  primary_conninfo = 'host=pg-0.postgres-headless port=5432 user=replicator'

  # pg-2 connects to pg-0 for replication:
  primary_conninfo = 'host=pg-0.postgres-headless port=5432 user=replicator'
```

```
Production Architecture:

  order-service ----+
                    |
  user-service  ----+--> postgres-service (ClusterIP) --+--> pg-0 (reads)
                    |    (load balanced reads)          +--> pg-1 (reads)
  payment-service --+                                   +--> pg-2 (reads)

  order-service ---------> pg-0.postgres-headless ---------> pg-0 (writes only)
  (write queries)          (direct to primary)

  pg-1 ---------------------> pg-0.postgres-headless ------> pg-0
  pg-2 ---------------------> pg-0.postgres-headless ------> pg-0
  (replicas pull WAL from primary using headless DNS)
```

---

## Demo 5: Scale and Observe

### Scale up

```bash
# Scale from 3 to 5
kubectl scale statefulset pg -n database --replicas=5

kubectl get pods -n database -w
# pg-3   0/1   Pending   0   0s      <-- created after pg-2
# pg-3   1/1   Running   0   20s
# pg-4   0/1   Pending   0   0s      <-- created after pg-3
# pg-4   1/1   Running   0   18s

# New PVCs created
kubectl get pvc -n database
# postgres-data-pg-0  Bound   20Gi
# postgres-data-pg-1  Bound   20Gi
# postgres-data-pg-2  Bound   20Gi
# postgres-data-pg-3  Bound   20Gi    <-- new EBS volume
# postgres-data-pg-4  Bound   20Gi    <-- new EBS volume

# Total: 5 x 20Gi = 100GB EBS storage
```

### Scale down

```bash
# Scale back to 3
kubectl scale statefulset pg -n database --replicas=3

kubectl get pods -n database -w
# pg-4   Terminating   <-- highest ordinal deleted first
# pg-3   Terminating   <-- then next highest

# PVCs for pg-3 and pg-4 still exist (data preserved)
kubectl get pvc -n database
# postgres-data-pg-3  Bound   20Gi    <-- still here!
# postgres-data-pg-4  Bound   20Gi    <-- still here!

# If you scale back up to 5, pg-3 and pg-4 will reattach to their old PVCs
```

```
Scale Down Behavior:

  Pods:  pg-4 deleted --> pg-3 deleted (reverse order)
  PVCs:  postgres-data-pg-3, postgres-data-pg-4 REMAIN
  EBS:   Both EBS volumes still exist in AWS (you keep paying!)

  To actually free the storage:
  kubectl delete pvc postgres-data-pg-3 postgres-data-pg-4 -n database

  With reclaimPolicy: Retain, you must also manually delete EBS in AWS
  With reclaimPolicy: Delete, EBS is auto-deleted when PVC is deleted
```

---

## Clean Up

```bash
# Delete the order-service (demo microservice)
kubectl delete deployment order-service -n database

# Delete the StatefulSet (pods go away)
kubectl delete statefulset pg -n database

# Delete services
kubectl delete svc postgres-service postgres-headless -n database

# Delete secret
kubectl delete secret postgres-secret -n database

# Delete PVCs (THIS deletes the data binding)
kubectl delete pvc -l app=postgres -n database
# OR delete individually:
kubectl delete pvc postgres-data-pg-0 postgres-data-pg-1 postgres-data-pg-2 -n database

# With reclaimPolicy: Retain, EBS volumes still exist in AWS!
# Check and delete manually:
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=database" \
  --query "Volumes[*].{ID:VolumeId,Size:Size,State:State}" --output table

# Delete the namespace
kubectl delete namespace database

# Delete StorageClass (if not used elsewhere)
kubectl delete sc ebs-gp3
```

---

## Summary

```
+-----------------------------------------------------------+
| What We Built                                              |
+-----------------------------------------------------------+
| PostgreSQL StatefulSet with:                               |
|   - 3 replicas (pg-0, pg-1, pg-2)                        |
|   - Each with its own 20GB EBS gp3 volume                 |
|   - Encrypted storage with Retain policy                   |
|   - subPath (pgdata) for the data directory               |
|   - Secrets for credentials                                |
|                                                            |
| (Hardening you'd add next: liveness/readiness probes,      |
|  resource requests/limits, ConfigMap tuning, real          |
|  streaming replication or a Postgres operator.)            |
|                                                            |
| Two Services:                                              |
|   - postgres-service (ClusterIP) for app connections       |
|   - postgres-headless (None) for replication + direct access|
|                                                            |
| App Connection:                                            |
|   - Microservices connect via postgres-service             |
|   - Cross-namespace: postgres-service.database.svc...      |
+-----------------------------------------------------------+
```

### Production Checklist

| Item | What We Did | Why |
|------|------------|-----|
| StorageClass | gp3, encrypted, Retain | Fast SSD, data protection |
| Secrets | Kubernetes Secret for passwords | Don't hardcode credentials |
| Headless Service | clusterIP: None | StatefulSet requirement + replication |
| Regular Service | ClusterIP | App connections (load balanced) |
| volumeClaimTemplates | 20Gi per replica | Each pod gets its own EBS |
| subPath | pgdata subdirectory | PostgreSQL requires non-root directory |
| Retain policy | Don't auto-delete EBS | Protect against accidental deletion |

> **Not yet done (next steps to "real" production):** liveness/readiness probes, resource requests & limits, a `ConfigMap` for `postgresql.conf` tuning, and **actual streaming replication** (replication user + `primary_conninfo`, or a Postgres operator like CloudNativePG / Zalando). The 3 pods here are independent instances.

### Key Takeaways

1. **Two services are needed**: headless (for StatefulSet + direct pod access) and regular (for app connections)
2. **Your microservices connect to the regular service** (`postgres-service`), not the headless one
3. **For writes, connect to primary directly**: `pg-0.postgres-headless` via headless service DNS
4. **Cross-namespace connections** use full DNS: `postgres-service.database.svc.cluster.local`
5. **subPath is important** for PostgreSQL -- it needs data in a subdirectory, not the volume root
6. **Always use Retain** reclaim policy for database storage -- never risk auto-deletion
7. **PVCs survive** StatefulSet deletion -- your data is safe even if you delete everything
8. **Each replica gets its own EBS** -- 3 replicas = 3 x 20GB = 60GB total storage cost

---

## Common Mistakes

1. **CSI driver / StorageClass not ready.** Without the **EBS CSI driver + IRSA** and the `ebs-gp3` class, every PVC sits `Pending`. Finish the [Day 13 EKS setup](../day13-volumes-demo/eks-demo.md) first.
2. **Omitting `subPath: pgdata`.** PostgreSQL refuses to initialise in a volume root that contains `lost+found`. The data dir must be a **subdirectory** of the mount.
3. **`Immediate` binding across AZs.** EBS is AZ-locked; a volume in the wrong AZ can never attach. Use `volumeBindingMode: WaitForFirstConsumer`.
4. **Assuming the 3 pods replicate automatically.** They're **independent** instances here. Real replication needs explicit config or an operator - Kubernetes doesn't copy DB data for you.
5. **Leaving EBS behind on cleanup.** StatefulSet deletion **retains** PVCs, and `Retain` keeps the EBS even after PVC deletion. Verify with `aws ec2 describe-volumes` or you keep paying.

---

## Quick Self-Check

1. Why must the EBS CSI driver and `ebs-gp3` StorageClass exist before this StatefulSet will run?
2. What PVC names does `volumeClaimTemplates: name: postgres-data` produce for replicas `pg-0..pg-2`?
3. Which service do your app's **read** queries use, and which address would a **write** go to?
4. After deleting `pg-0`, why is the previously inserted `orders` data still there?
5. After `kubectl delete statefulset pg` with `reclaimPolicy: Retain`, what two things must you do to fully stop AWS charges?

<details>
<summary>Answers</summary>

1. They provide **dynamic provisioning of real EBS volumes**; without them PVCs can't bind and pods stay `Pending`.
2. `postgres-data-pg-0`, `postgres-data-pg-1`, `postgres-data-pg-2` (pattern `<template>-<statefulset>-<ordinal>`).
3. **Reads** -> `postgres-service` (regular ClusterIP, load-balanced). **Writes** -> `pg-0.postgres-headless` (direct to the primary via headless DNS).
4. The recreated `pg-0` keeps the **same identity** and **re-attaches `postgres-data-pg-0`** (its own EBS), so the data persists.
5. **Delete the PVCs** (`kubectl delete pvc -l app=postgres -n database`) **and** delete the retained **EBS volumes in AWS** (`aws ec2 delete-volume ...`), confirming with `describe-volumes`.

</details>

---

## Summary

- PostgreSQL on EKS uses `volumeClaimTemplates` + the EBS CSI driver to give each pod its **own real EBS volume**.
- `WaitForFirstConsumer` keeps each EBS in the **same AZ** as its pod.
- **Two services**: `postgres-service` (reads, load-balanced) and `postgres-headless` (direct/writes/replication).
- Identity sticks to storage: delete `pg-0`, it returns with `postgres-data-pg-0` and its data intact.
- Use **Retain** for safety, but then **clean up PVCs and EBS explicitly** to avoid charges.

---

> **Production hardening to explore next:** liveness/readiness probes & resource limits, a Postgres **operator** (CloudNativePG / Zalando), EBS **snapshots/backups**, and multi-AZ HA.

**Next up ->** [Day 16 - Resource Management and Autoscaling](../day16-resource-management-autoscaling/notes.md)

**Previous:** [StatefulSets Demo (Local)](notes.md) | **Theory:** [Day 14 - StatefulSets](../day14-statefulsets/notes.md)
