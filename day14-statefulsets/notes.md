# Day 14 - StatefulSets

## The Problem: Why Can't We Use Deployments for Everything?

Deployments work great for **stateless** applications like web servers and API services. But what about **stateful** applications like databases?

Let's see what goes wrong when you try to run a database with a Deployment:

```
Deployment with 3 replicas of MySQL:

  Pod: mysql-7d8f9a-abc    ← random name, could be deleted and recreated
  Pod: mysql-7d8f9a-def    ← random name, no identity
  Pod: mysql-7d8f9a-ghi    ← random name, no ordering

Problems:
  1. Pod names are RANDOM -- you can't reliably address a specific pod
  2. All pods share the SAME PersistentVolume -- data corruption!
  3. Pods are created/deleted in RANDOM order -- database can't elect a primary
  4. When a pod restarts, it gets a NEW name -- other pods lose track of it
```

### Stateless vs Stateful Applications

```
Stateless (Deployment):              Stateful (StatefulSet):
- Web servers                        - Databases (MySQL, PostgreSQL)
- API services                       - Message queues (Kafka, RabbitMQ)
- Microservices                      - Distributed stores (ZooKeeper, etcd)
- Any pod is identical               - Each pod has a unique role/identity
- No persistent identity needed      - Needs stable hostname & storage
- Scale freely                       - Order of creation matters
```

---

## What Is a StatefulSet?

A StatefulSet is like a Deployment but with **guarantees** for stateful applications:

```
┌────────────────── StatefulSet: mysql ──────────────────┐
│                                                         │
│  mysql-0          mysql-1          mysql-2               │
│  (Primary)        (Replica)        (Replica)            │
│  ┌──────┐         ┌──────┐         ┌──────┐            │
│  │ Pod  │         │ Pod  │         │ Pod  │            │
│  │      │         │      │         │      │            │
│  └──┬───┘         └──┬───┘         └──┬───┘            │
│     │                │                │                 │
│  ┌──┴───┐         ┌──┴───┐         ┌──┴───┐            │
│  │ PVC  │         │ PVC  │         │ PVC  │            │
│  │ (own)│         │ (own)│         │ (own)│            │
│  └──────┘         └──────┘         └──────┘            │
│                                                         │
│  Features:                                              │
│  - Predictable names: mysql-0, mysql-1, mysql-2        │
│  - Each pod has its OWN PersistentVolumeClaim           │
│  - Created in order: 0 → 1 → 2                        │
│  - Deleted in reverse: 2 → 1 → 0                      │
│  - Stable hostname via Headless Service                 │
└─────────────────────────────────────────────────────────┘
```

---

## StatefulSet Features in Detail

### Feature 1: Stable, Predictable Pod Names

```
Deployment pods:                    StatefulSet pods:
  nginx-7d8f9a-xk2lp                 web-0
  nginx-7d8f9a-m9nrq                 web-1
  nginx-7d8f9a-p3j7t                 web-2

  Random suffixes!                    Sequential, predictable!
  Changes on restart!                 Same name even after restart!
```

If `web-1` crashes and restarts, it comes back as `web-1` (not a random name). This is crucial for databases where other pods need to know exactly who is who.

### Feature 2: Ordered Creation and Deletion

```
Creation (scale up):
  web-0: Creating... Running!
  web-1:                       Creating... Running!
  web-2:                                              Creating... Running!

  Each pod must be READY before the next one starts.
  This ensures the primary DB is up before replicas connect.

Deletion (scale down):
  web-2: Terminating... Gone!
  web-1:                       Terminating... Gone!
  web-0:                                              Terminating... Gone!

  Deleted in REVERSE order. The primary (web-0) is the last to go.
```

### Feature 3: Stable Network Identity

Each pod gets a **stable DNS name** through a Headless Service:

```
Headless Service: mysql-headless (clusterIP: None)

Pod DNS names:
  mysql-0.mysql-headless.default.svc.cluster.local
  mysql-1.mysql-headless.default.svc.cluster.local
  mysql-2.mysql-headless.default.svc.cluster.local

  These DNS names NEVER change, even if the pod restarts!

  Other pods can connect to:
    mysql-0.mysql-headless   ← always reaches the primary
    mysql-1.mysql-headless   ← always reaches replica 1
```

### Feature 4: Per-Pod Persistent Storage

```
Deployment (shared storage):
  ┌─────┐  ┌─────┐  ┌─────┐
  │Pod 1│  │Pod 2│  │Pod 3│    All pods read/write
  └──┬──┘  └──┬──┘  └──┬──┘    to the SAME volume
     │        │        │        → Data corruption!
     └────────┴────────┘
              │
         ┌────┴────┐
         │   PVC   │
         │ (shared)│
         └─────────┘

StatefulSet (individual storage):
  ┌─────┐    ┌─────┐    ┌─────┐
  │Pod 0│    │Pod 1│    │Pod 2│    Each pod has its
  └──┬──┘    └──┬──┘    └──┬──┘    OWN volume
     │          │          │        → Safe!
  ┌──┴──┐    ┌──┴──┐    ┌──┴──┐
  │PVC-0│    │PVC-1│    │PVC-2│
  └─────┘    └─────┘    └─────┘
```

When a StatefulSet pod is deleted and recreated, it **reattaches to the same PVC**. Your data survives pod restarts!

---

## What Is a Headless Service?

A regular Service gives you a **single IP** (load balancer). A Headless Service gives you the **individual pod IPs** directly.

```
Regular Service (clusterIP: 10.96.0.1):
  Client → 10.96.0.1 → (load balanced to any pod)
  You don't know WHICH pod you'll reach

Headless Service (clusterIP: None):
  Client → DNS lookup "mysql-headless"
         → Returns ALL pod IPs:
            10.244.0.5 (mysql-0)
            10.244.1.3 (mysql-1)
            10.244.2.7 (mysql-2)
         → Client can connect to a SPECIFIC pod!

  Client → mysql-0.mysql-headless → always reaches mysql-0
```

### Headless Service YAML

```yaml
# headless-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None              # <-- This makes it "headless"
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
```

The key difference: `clusterIP: None`. No virtual IP is assigned. DNS resolves directly to pod IPs.

---

## StatefulSet YAML

```yaml
# statefulset-mysql.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless     # REQUIRED: must reference a Headless Service
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "rootpass"
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:           # <-- Creates a unique PVC for each pod
  - metadata:
      name: mysql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### Key Differences from a Deployment

```yaml
# Deployment:
kind: Deployment
spec:
  replicas: 3
  # Uses a shared PVC (or you manage volumes separately)
  # No serviceName field
  # No volumeClaimTemplates

# StatefulSet:
kind: StatefulSet
spec:
  serviceName: mysql-headless     # REQUIRED for StatefulSets
  replicas: 3
  volumeClaimTemplates:           # Creates PVC-per-pod automatically
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

---

## volumeClaimTemplates Explained

```yaml
volumeClaimTemplates:
- metadata:
    name: mysql-data              # Template name
  spec:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 10Gi
```

This is a **template**. For each pod, Kubernetes creates a PVC named:

```
Pod: mysql-0 → PVC: mysql-data-mysql-0
Pod: mysql-1 → PVC: mysql-data-mysql-1
Pod: mysql-2 → PVC: mysql-data-mysql-2

Format: {volumeClaimTemplate.name}-{statefulset.name}-{ordinal}
```

```bash
# See the auto-created PVCs
kubectl get pvc
# NAME                  STATUS   VOLUME   CAPACITY   ACCESS MODES
# mysql-data-mysql-0    Bound    pv-001   10Gi       RWO
# mysql-data-mysql-1    Bound    pv-002   10Gi       RWO
# mysql-data-mysql-2    Bound    pv-003   10Gi       RWO
```

> **Important:** When you delete a StatefulSet, the PVCs are NOT deleted. This is intentional -- it protects your data. You must delete PVCs manually if you want to remove the data.

---

## StatefulSet vs Deployment Comparison

| Feature | Deployment | StatefulSet |
|---------|-----------|-------------|
| Pod names | Random (nginx-abc123) | Sequential (web-0, web-1) |
| Pod identity | No stable identity | Stable, persistent identity |
| Creation order | All at once (parallel) | One by one (sequential) |
| Deletion order | Random | Reverse sequential |
| Storage | Shared PVC or none | Unique PVC per pod |
| Network identity | Via Service (random pod) | Via Headless Service (specific pod) |
| Pod restart | New random name | Same name, same PVC |
| Use case | Stateless apps | Stateful apps (databases) |

---

## When to Use StatefulSets

### Use StatefulSets For:
- **Databases:** MySQL, PostgreSQL, MongoDB, Cassandra
- **Message brokers:** Kafka, RabbitMQ
- **Coordination services:** ZooKeeper, etcd, Consul
- **Search engines:** Elasticsearch
- Any application that needs **stable identity** or **persistent per-pod storage**

### Don't Use StatefulSets For:
- Web servers (use Deployment)
- Stateless APIs (use Deployment)
- Batch processing (use Jobs)
- Applications that don't need persistent storage or identity

### Decision Flow

```
Does your app need persistent storage per instance?
  │
  ├── No ──→ Use Deployment
  │
  └── Yes
      │
      Does each instance need a unique identity?
        │
        ├── No ──→ Use Deployment + PVC
        │
        └── Yes ──→ Use StatefulSet
```

---

## StatefulSet Update Strategies

```yaml
spec:
  updateStrategy:
    type: RollingUpdate          # Default: update one pod at a time
    rollingUpdate:
      partition: 2               # Only update pods with ordinal >= 2
```

| Strategy | Behavior |
|----------|----------|
| `RollingUpdate` (default) | Update pods one at a time, in reverse order (N-1 down to 0) |
| `OnDelete` | Only update a pod when you manually delete it |

The `partition` field enables **canary deployments**: set `partition: 2` to only update `web-2`, while `web-0` and `web-1` stay on the old version.

```
updateStrategy with partition: 2

  web-0: old version (not updated, ordinal < 2)
  web-1: old version (not updated, ordinal < 2)
  web-2: NEW version (updated, ordinal >= 2)  ← canary!
```

---

## Working with StatefulSets

```bash
# Create the StatefulSet
kubectl apply -f statefulset-mysql.yaml

# Watch pods being created IN ORDER
kubectl get pods -w
# NAME      READY   STATUS    AGE
# mysql-0   0/1     Pending   0s
# mysql-0   1/1     Running   5s     ← Ready!
# mysql-1   0/1     Pending   6s     ← Starts only AFTER mysql-0 is ready
# mysql-1   1/1     Running   11s
# mysql-2   0/1     Pending   12s
# mysql-2   1/1     Running   17s

# Scale the StatefulSet
kubectl scale statefulset mysql --replicas=5
# mysql-3 created, then mysql-4

# Scale down
kubectl scale statefulset mysql --replicas=3
# mysql-4 deleted, then mysql-3 (reverse order)

# Check PVCs (they persist even if pods are deleted)
kubectl get pvc

# Delete the StatefulSet
kubectl delete statefulset mysql

# PVCs still exist!
kubectl get pvc
# NAME                  STATUS   VOLUME
# mysql-data-mysql-0    Bound    pv-001    ← Data preserved!
# mysql-data-mysql-1    Bound    pv-002
# mysql-data-mysql-2    Bound    pv-003

# Manually delete PVCs if you want to remove data
kubectl delete pvc mysql-data-mysql-0 mysql-data-mysql-1 mysql-data-mysql-2
```

---

## Complete Example: MySQL with StatefulSet

```yaml
# mysql-statefulset-complete.yaml

# 1. Headless Service (required for StatefulSet)
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  labels:
    app: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
---
# 2. Regular Service (for client connections)
apiVersion: v1
kind: Service
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
---
# 3. StatefulSet
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
        livenessProbe:
          exec:
            command: ["mysqladmin", "ping", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["mysql", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}", "-e", "SELECT 1"]
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: mysql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
---
# 4. Secret for MySQL password
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
stringData:
  root-password: "my-secure-password"
```

---

## How Database Replication Actually Works with StatefulSets

### The Wrong Way: Shared Disk (DON'T Do This)

```
2 MySQL replicas sharing 1 EFS volume:

MySQL-0 ---write---> EFS <---read--- MySQL-1
                      ^
        MySQL-1 doesn't know WHAT changed or WHEN
        Has to guess, read entire disk
        Both engines managing same data = logical corruption
```

Why this fails: each MySQL keeps data in **RAM (buffer pool)** for speed.
They don't read from disk for every query. So when MySQL-0 writes to disk,
MySQL-1 still has OLD data in its RAM and makes wrong decisions.

> For the full detailed explanation with the "accountant analogy", see:
> [Why You Can't Use EFS for Databases](../day12-volumes/aws-volumes/notes.md#deep-dive-why-you-cant-use-efs-for-databases)

### The Right Way: Separate Disks + Network Replication

Each replica has **its own disk, its own memory, its own data**. They sync using
the **database's own replication protocol over the network**.

```
MySQL-0 (Primary)                    MySQL-1 (Replica)
+------------------+                 +------------------+
| RAM: A=$500      |                 | RAM: A=$500      |
| Disk: EBS-0      |                 | Disk: EBS-1      |
+--------+---------+                 +--------+---------+
         |                                    |
         +---- network (MySQL replication) ---+
```

### Step by Step: How MySQL Replication Works

```
1. Customer writes to Primary (MySQL-0):
   "Transfer $100 from A"

2. MySQL-0 (Primary):
   - Updates RAM: A = $400
   - Writes to its own EBS-0: A = $400
   - Writes to BINLOG: "Changed A from $500 to $400"
                         ^
                    this is the replication log

3. MySQL-0 sends binlog over NETWORK to MySQL-1:
   "Hey, I changed A to $400"
        |
        |  network (not shared disk!)
        v
4. MySQL-1 (Replica):
   - Receives the binlog entry
   - Updates its own RAM: A = $400
   - Writes to its own EBS-1: A = $400

5. Both are in sync now:
   MySQL-0: RAM = $400, EBS-0 = $400
   MySQL-1: RAM = $400, EBS-1 = $400
```

**The key:** MySQL-1 doesn't read from MySQL-0's disk. It receives **instructions**
("change A to $400") and applies them to its own disk. Both databases are always
aware of every change.

### Different Databases, Same Concept

| Database | Replication Protocol | How It Works |
|----------|---------------------|--------------|
| MySQL | **Binlog** (binary log) | Primary logs every change, replicas replay the log |
| PostgreSQL | **WAL streaming** (write-ahead log) | Primary streams WAL records to replicas |
| MongoDB | **Oplog** (operations log) | Primary logs operations, secondaries tail the oplog |
| Kafka | **ISR** (in-sync replicas) | Leader partition replicates to follower partitions |

They all follow the same pattern:
1. Primary writes data to its own disk
2. Primary logs the change
3. Sends the log to replicas over network
4. Replicas apply the change to their own disk

### Full Picture in Kubernetes

```
StatefulSet: mysql (3 replicas)

mysql-0 (Primary)          mysql-1 (Replica)         mysql-2 (Replica)
+--------------+           +--------------+          +--------------+
|  MySQL       |           |  MySQL       |          |  MySQL       |
|  Engine      |--binlog-->|  Engine      |--binlog->|  Engine      |
|              |  network  |              | network  |              |
+------+-------+           +------+-------+          +------+-------+
       |                          |                         |
   PVC-0                      PVC-1                     PVC-2
       |                          |                         |
   EBS-0                      EBS-1                     EBS-2
(own disk)                 (own disk)                (own disk)
```

### What Kubernetes Does vs What the Database Does

```
Kubernetes provides:
  - Stable pod names (mysql-0, mysql-1, mysql-2)
  - Stable DNS (mysql-0.mysql-headless)
  - Stable storage (PVC per replica, reattaches on restart)
  - Ordered startup (primary first, then replicas)

The DATABASE handles:
  - Data replication (binlog, WAL, oplog)
  - Primary election (who is the writer?)
  - Consistency (are all replicas in sync?)
  - Failover (primary dies, promote a replica)

Kubernetes does NOT replicate data. It just gives the database
a stable environment to do its own replication.
```

### Interview Answer

```
Q: "How does data replication work in StatefulSets?"

A: "Kubernetes StatefulSets don't replicate data. They provide stable names,
   stable storage, and ordered startup. The database itself handles replication
   using its own protocol -- MySQL uses binlog, PostgreSQL uses WAL streaming,
   MongoDB uses oplog. Each replica has its own PVC (own EBS volume), and the
   primary sends change logs to replicas over the network. This is why we use
   StatefulSets with per-pod storage (volumeClaimTemplates) instead of shared
   storage -- each database instance needs exclusive access to its own data."
```

---

## Key Takeaways

1. **StatefulSets** are for stateful applications that need stable identity and persistent storage
2. Pods get **predictable names**: `name-0`, `name-1`, `name-2` (not random)
3. Pods are created **in order** (0, 1, 2) and deleted **in reverse** (2, 1, 0)
4. Each pod gets its **own PVC** via `volumeClaimTemplates` -- no shared storage conflicts
5. **Headless Service** (clusterIP: None) provides stable DNS names for each pod
6. Pod DNS format: `{pod-name}.{headless-service}.{namespace}.svc.cluster.local`
7. PVCs are **NOT deleted** when the StatefulSet is deleted -- this protects your data
8. The `serviceName` field in StatefulSet spec is **required** and must match a Headless Service
9. Use the `partition` field for canary deployments of StatefulSets
10. Only use StatefulSets when you actually need stable identity or per-pod storage. For stateless apps, Deployments are simpler and better
11. **Kubernetes does NOT replicate data** -- it provides stable names, DNS, and storage. The database handles replication using its own protocol (binlog, WAL, oplog)
12. **Never share a single volume across database replicas** -- each replica needs exclusive disk access. Use `volumeClaimTemplates` for per-replica EBS
13. **Database replication happens over the network**, not shared storage. Primary sends change logs to replicas, each replica applies changes to its own disk

---

## Practice / Homework

1. Create a Headless Service and a StatefulSet with 3 replicas
2. Watch the pods being created in order
3. Check the auto-created PVCs
4. Use `nslookup` from inside a pod to resolve StatefulSet pod DNS names
5. Delete the StatefulSet and verify the PVCs still exist
6. Recreate the StatefulSet and verify pods reattach to their original PVCs

---

**Previous:** [<-- Day 13 - Volumes Demo](../day13-volumes-demo/notes.md)
**Next:** [Day 15 - StatefulSets Demo -->](../day15-statefulsets-demo/notes.md)
