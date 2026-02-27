# AWS Volumes for Kubernetes (EBS & EFS) - Production Guide

## Why Not hostPath in Production?

```
hostPath problems:
  ❌ Data is on ONE node only → pod moves to another node → data LOST
  ❌ No replication → node disk fails → data GONE forever
  ❌ No dynamic provisioning → admin must manually create directories
  ❌ Security risk → pod can access any path on the node

AWS volumes solve all of this:
  ✅ EBS: Block storage, automatically attaches to the right node
  ✅ EFS: Shared file storage, multiple pods/nodes can read-write
  ✅ Dynamic provisioning with StorageClass
  ✅ Automatic snapshots, encryption, high availability
```

---

## Two Types of AWS Storage for K8s

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  EBS (Elastic Block Store)          EFS (Elastic File System)  │
│  ========================          ========================    │
│                                                                │
│  Like a USB drive                   Like a shared network      │
│  attached to ONE server             folder (NFS)               │
│                                                                │
│  ┌──── Node 1 ────┐               ┌──── Node 1 ────┐         │
│  │ Pod-A           │               │ Pod-A           │         │
│  │   ↓             │               │   ↓             │         │
│  │ [EBS Volume]    │               │   │             │         │
│  └─────────────────┘               └───┼─────────────┘         │
│                                        │                       │
│  ┌──── Node 2 ────┐               ┌───┼── Node 2 ───┐         │
│  │ Pod-B           │               │ Pod-B           │         │
│  │   ↓             │               │   ↓             │         │
│  │ [Different EBS] │               │   │             │         │
│  └─────────────────┘               └───┼─────────────┘         │
│                                        │                       │
│  Pod-A and Pod-B                       ▼                       │
│  CANNOT share the                  ┌───────────┐              │
│  same EBS volume!                  │  EFS      │              │
│                                    │  (shared) │              │
│  One EBS = One Node                │           │              │
│                                    └───────────┘              │
│                                    ALL pods share             │
│                                    the SAME EFS!              │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### When to Use What

| Feature | EBS | EFS |
|---------|-----|-----|
| **Access mode** | ReadWriteOnce (one node) | ReadWriteMany (many nodes) |
| **Use case** | Databases (MySQL, Postgres) | Shared files (uploads, configs, CMS) |
| **Performance** | Very fast (SSD, io2) | Good (not as fast as EBS) |
| **Cost** | Cheaper per GB | More expensive per GB |
| **Availability** | Single AZ only | Multi-AZ (highly available) |
| **Max size** | 64 TB | Petabytes (unlimited) |
| **Shared access** | No | Yes |
| **Best for** | Single-pod stateful apps | Multi-pod shared storage |

```
Decision:
  Need shared storage across pods/nodes? → EFS
  Single pod database or cache?          → EBS
  Need highest performance?              → EBS (io2/gp3)
  Need multi-AZ availability?            → EFS
```

---

## Part 1: EBS Volumes on EKS

### Prerequisites

```bash
# 1. EKS cluster must have the EBS CSI Driver installed
# Check if it's already installed:
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# 2. If not installed, add it as an EKS add-on:
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-ebs-csi-driver \
  --region ap-south-1

# OR install via eksctl:
eksctl create addon \
  --cluster my-cluster \
  --name aws-ebs-csi-driver \
  --region ap-south-1

# 3. Verify
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
# NAME                                 READY   STATUS    RESTARTS   AGE
# ebs-csi-controller-xxxxxxxxx-xxxxx   6/6     Running   0          5m
# ebs-csi-node-xxxxx                   3/3     Running   0          5m
```

### IAM Permissions Needed

```
The EBS CSI Driver needs permission to:
  - Create/Delete EBS volumes
  - Attach/Detach volumes to EC2 instances
  - Create snapshots

This is done via IAM Role for Service Account (IRSA):

eksctl create iamserviceaccount \
  --cluster my-cluster \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve
```

### EBS Volume Types

```
gp3 (General Purpose SSD) ← RECOMMENDED for most workloads
  - 3,000 IOPS baseline (free)
  - Up to 16,000 IOPS
  - $0.08/GB/month
  - Best price-performance

gp2 (Older General Purpose)
  - IOPS depends on size (3 IOPS per GB)
  - Up to 16,000 IOPS
  - Same price as gp3 but worse performance
  - Being replaced by gp3

io2 (Provisioned IOPS SSD)
  - Up to 64,000 IOPS
  - For databases needing guaranteed high IOPS
  - Expensive: $0.125/GB + $0.065/IOPS/month

st1 (Throughput Optimized HDD)
  - Cheap, high throughput
  - For big data, log processing
  - Cannot be boot volume
```

### Two Ways to Provision EBS in Kubernetes

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  Static Provisioning              Dynamic Provisioning               │
│  ====================             =====================              │
│                                                                      │
│  YOU create EBS in AWS            KUBERNETES creates EBS for you     │
│  YOU create PV manually           StorageClass + PVC → auto PV      │
│  YOU create PVC                   Just create PVC → done!            │
│                                                                      │
│  Admin creates EBS                Pod needs storage                  │
│       ↓                                ↓                             │
│  Admin creates PV                 PVC requests StorageClass          │
│       ↓                                ↓                             │
│  Admin creates PVC                CSI driver creates EBS             │
│       ↓                                ↓                             │
│  Pod uses PVC                     PV created automatically           │
│                                        ↓                             │
│  4 manual steps!                  Pod uses PVC                       │
│                                                                      │
│                                   2 steps! (StorageClass + PVC)      │
│                                                                      │
│  When to use:                     When to use:                       │
│  - Pre-existing EBS volumes       - New applications (most cases)    │
│  - Migrating data from old setup  - Auto-scaling environments        │
│  - Specific volume requirements   - When you want automation         │
│  - Learning/understanding flow    - Production (recommended)         │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

### Method 1: Static Provisioning (Manual)

```
Flow: Create EBS in AWS → Create PV in K8s → Create PVC → Pod uses PVC

This is the "old school" way. You do everything manually.
Good for understanding how PV/PVC works under the hood.
```

#### Step 1: Create an EBS Volume in AWS

```bash
# Create a 20GB gp3 EBS volume in ap-south-1a
aws ec2 create-volume \
  --availability-zone ap-south-1a \
  --size 20 \
  --volume-type gp3 \
  --encrypted \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=mysql-data}]'

# Output:
# {
#     "VolumeId": "vol-0abc123def456789",    ← Note this ID!
#     "Size": 20,
#     "VolumeType": "gp3",
#     "AvailabilityZone": "ap-south-1a",
#     "State": "creating"
# }

# Wait for it to be available:
aws ec2 describe-volumes --volume-ids vol-0abc123def456789 --query "Volumes[0].State"
# "available"
```

#### Step 2: Create a PersistentVolume (PV) in Kubernetes

```yaml
# ebs-static-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-ebs-pv
spec:
  capacity:
    storage: 20Gi                          # ← Must match EBS size
  accessModes:
    - ReadWriteOnce                        # ← EBS is always RWO
  persistentVolumeReclaimPolicy: Retain    # ← Don't delete EBS when PVC is removed
  storageClassName: ""                     # ← Empty = no StorageClass (static)
  csi:
    driver: ebs.csi.aws.com               # ← EBS CSI driver
    volumeHandle: vol-0abc123def456789     # ← Your EBS Volume ID from Step 1!
    fsType: ext4
  nodeAffinity:                            # ← Tell K8s which AZ this volume is in
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.ebs.csi.aws.com/zone
          operator: In
          values:
          - ap-south-1a                    # ← Must match the EBS volume's AZ
```

```bash
kubectl apply -f ebs-static-pv.yaml
# persistentvolume/mysql-ebs-pv created

kubectl get pv
# NAME           CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS   AGE
# mysql-ebs-pv   20Gi       RWO            Retain           Available                  5s
```

#### Step 3: Create a PVC That Binds to This PV

```yaml
# ebs-static-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""                     # ← Empty = look for static PVs only
  resources:
    requests:
      storage: 20Gi                        # ← Must match PV capacity
  volumeName: mysql-ebs-pv                 # ← Bind to this specific PV
```

```bash
kubectl apply -f ebs-static-pvc.yaml
# persistentvolumeclaim/mysql-ebs-pvc created

kubectl get pvc
# NAME            STATUS   VOLUME         CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# mysql-ebs-pvc   Bound    mysql-ebs-pv   20Gi       RWO                           5s

# Status is "Bound" immediately because we specified volumeName!
```

#### Step 4: Use in a Pod

```yaml
# mysql-static.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
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
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpass123
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-data
        persistentVolumeClaim:
          claimName: mysql-ebs-pvc         # ← Uses our static PVC
```

```bash
kubectl apply -f mysql-static.yaml

kubectl get pods -l app=mysql
# NAME                     READY   STATUS    RESTARTS   AGE
# mysql-xxxxxxxxx-xxxxx    1/1     Running   0          30s
```

#### Static Provisioning Clean Up

```bash
kubectl delete deployment mysql
kubectl delete pvc mysql-ebs-pvc

# IMPORTANT: With reclaimPolicy: Retain, the PV and EBS volume are NOT deleted!
kubectl get pv
# NAME           CAPACITY   STATUS     RECLAIM POLICY   AGE
# mysql-ebs-pv   20Gi       Released   Retain           10m

# You must manually delete:
kubectl delete pv mysql-ebs-pv
aws ec2 delete-volume --volume-id vol-0abc123def456789
```

```
Why "Retain" for static provisioning?
  - You created the EBS manually → you should delete it manually
  - Prevents accidental data loss
  - For dynamic provisioning, "Delete" is fine because K8s created it
```

---

### Method 2: Dynamic Provisioning (Recommended for Production)

```
Flow: Create StorageClass (once) → Create PVC → K8s auto-creates EBS + PV → Pod uses PVC

No need to create EBS volumes or PVs manually!
The CSI driver handles everything automatically.
```

#### Step 1: Create a StorageClass

```yaml
# ebs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com        # ← AWS EBS CSI driver
parameters:
  type: gp3                          # ← gp3 is the best general purpose SSD
  fsType: ext4                       # ← Linux filesystem
  encrypted: "true"                  # ← Encrypt data at rest!
reclaimPolicy: Delete                # ← Delete EBS when PVC is deleted
volumeBindingMode: WaitForFirstConsumer   # ← Create EBS in same AZ as pod
allowVolumeExpansion: true           # ← Allow resizing later
```

```bash
kubectl apply -f ebs-storageclass.yaml
# storageclass.storage.k8s.io/ebs-gp3 created

kubectl get sc
# NAME            PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE       AGE
# ebs-gp3         ebs.csi.aws.com   Delete          WaitForFirstConsumer    5s
# gp2 (default)   kubernetes.io/aws-ebs   Delete    WaitForFirstConsumer    7d
```

#### Step 2: Create a PVC

```yaml
# ebs-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce                  # ← EBS only supports RWO
  storageClassName: ebs-gp3          # ← Use our StorageClass
  resources:
    requests:
      storage: 20Gi                  # ← 20GB EBS volume
```

```bash
kubectl apply -f ebs-pvc.yaml
# persistentvolumeclaim/mysql-ebs-pvc created

kubectl get pvc
# NAME            STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# mysql-ebs-pvc   Pending                                      ebs-gp3        5s

# Status is "Pending" because volumeBindingMode is WaitForFirstConsumer
# It will create the EBS volume when a pod actually needs it
```

#### Step 3: Use in a MySQL Deployment

```yaml
# mysql-ebs.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1                        # ← Only 1 replica (EBS is RWO)
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
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
      volumes:
      - name: mysql-data
        persistentVolumeClaim:
          claimName: mysql-ebs-pvc   # ← Uses EBS storage
---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  password: cm9vdHBhc3MxMjM=        # base64 of "rootpass123"
```

```bash
# Create the secret and deployment
kubectl apply -f mysql-ebs.yaml

# Check pod - it triggers EBS volume creation
kubectl get pods -l app=mysql -w
# NAME                     READY   STATUS    RESTARTS   AGE
# mysql-xxxxxxxxx-xxxxx    1/1     Running   0          45s

# Now check PVC - it's Bound!
kubectl get pvc mysql-ebs-pvc
# NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# mysql-ebs-pvc   Bound    pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   20Gi       RWO            ebs-gp3        2m

# Check in AWS Console:
# EC2 → Volumes → You'll see a new 20GB gp3 volume!
```

#### Step 4: Verify Data Persistence

```bash
# Add data to MySQL
kubectl exec -it $(kubectl get pod -l app=mysql -o name) -- \
  mysql -u root -prootpass123 -e "
    CREATE DATABASE IF NOT EXISTS testdb;
    USE testdb;
    CREATE TABLE IF NOT EXISTS users (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50));
    INSERT INTO users (name) VALUES ('Alice'), ('Bob');
    SELECT * FROM users;
  "

# Delete the pod (deployment recreates it)
kubectl delete pod -l app=mysql

# Wait for new pod
kubectl get pods -l app=mysql -w

# Check data - it's still there!
kubectl exec -it $(kubectl get pod -l app=mysql -o name) -- \
  mysql -u root -prootpass123 -e "SELECT * FROM testdb.users;"
# +----+-------+
# | id | name  |
# +----+-------+
# |  1 | Alice |
# |  2 | Bob   |
# +----+-------+
```

#### Expanding an EBS Volume

```bash
# Need more space? Edit the PVC:
kubectl edit pvc mysql-ebs-pvc
# Change storage from 20Gi to 50Gi

# OR patch it:
kubectl patch pvc mysql-ebs-pvc -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Check the resize status:
kubectl get pvc mysql-ebs-pvc
# CAPACITY will update to 50Gi after a few minutes

# This works because we set allowVolumeExpansion: true in StorageClass
# NOTE: You can only INCREASE size, never decrease!
```

### EBS with Multiple Replicas (Important!)

```
QUESTION: What if I have 3 replicas in a Deployment — can all 3 use the same EBS PVC?

ANSWER: NO! EBS is ReadWriteOnce (RWO) — only ONE node can mount it at a time.
```

#### Scenario 1: Deployment with 3 replicas + 1 EBS PVC

```
What you write:
  replicas: 3
  volumes:
    - persistentVolumeClaim:
        claimName: mysql-ebs-pvc    # ← All 3 replicas point to SAME PVC

What actually happens:

  ┌──── Node 1 ────────────┐     ┌──── Node 2 ────────────┐
  │                         │     │                         │
  │  Pod-1 (Running)        │     │  Pod-2 (STUCK!)         │
  │    ↓                    │     │    ↕                    │
  │  [EBS Volume attached]  │     │  "Multi-Attach error"   │
  │                         │     │                         │
  └─────────────────────────┘     │  Pod-3 (STUCK!)         │
                                  │    ↕                    │
                                  │  "Multi-Attach error"   │
                                  └─────────────────────────┘

  - Pod-1 gets the EBS and runs fine
  - Pod-2 and Pod-3 are stuck in "ContainerCreating" forever
  - Error: "Multi-Attach error for volume pvc-xxx"
  - Even if Pod-2 is on the SAME node as Pod-1, EBS still allows only 1 pod

Wait... actually if ALL 3 pods land on the SAME node, they CAN all mount it.
But Kubernetes spreads pods across nodes, so in practice it fails.
```

#### Scenario 2: The RIGHT way — StatefulSet (each replica gets its OWN EBS)

```
For databases where each replica needs its own storage (MySQL replicas,
MongoDB replica set, Kafka brokers), use StatefulSet with volumeClaimTemplates:
```

```yaml
# mysql-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  replicas: 3
  serviceName: mysql
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
        volumeMounts:
        - name: mysql-data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:            # ← THIS is the key!
  - metadata:
      name: mysql-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-gp3
      resources:
        requests:
          storage: 20Gi
```

```
What happens with StatefulSet + volumeClaimTemplates:

  ┌──── Node 1 ────────┐  ┌──── Node 2 ────────┐  ┌──── Node 3 ────────┐
  │                     │  │                     │  │                     │
  │  mysql-0 (Running)  │  │  mysql-1 (Running)  │  │  mysql-2 (Running)  │
  │    ↓                │  │    ↓                │  │    ↓                │
  │  [EBS-0: 20Gi]      │  │  [EBS-1: 20Gi]      │  │  [EBS-2: 20Gi]      │
  │                     │  │                     │  │                     │
  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘

  - Each replica gets its OWN PVC → its OWN EBS volume
  - mysql-data-mysql-0 → PVC for mysql-0 → unique EBS
  - mysql-data-mysql-1 → PVC for mysql-1 → unique EBS
  - mysql-data-mysql-2 → PVC for mysql-2 → unique EBS
  - Total: 3 × 20Gi = 60Gi EBS storage, 3 separate volumes
```

#### Scenario 3: Need shared storage across replicas? Use EFS!

```
If your app needs ALL replicas to read/write the SAME files:
  - WordPress with 3 replicas → all need the same uploads folder
  - A web app with 5 replicas → all serve the same static files

Solution: Use EFS (ReadWriteMany) instead of EBS!

  replicas: 3
  volumes:
    - persistentVolumeClaim:
        claimName: shared-efs-pvc    # ← EFS supports RWX

  ┌──── Node 1 ────┐  ┌──── Node 2 ────┐  ┌──── Node 3 ────┐
  │  Pod-1          │  │  Pod-2          │  │  Pod-3          │
  │    ↓            │  │    ↓            │  │    ↓            │
  └────┼────────────┘  └────┼────────────┘  └────┼────────────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                            ↓
                     ┌─────────────┐
                     │  EFS Volume  │
                     │  (shared)    │
                     └─────────────┘

  ALL 3 pods read/write the same files. No errors.
```

#### Summary Table

```
┌─────────────────────────────────┬────────────┬─────────────┬─────────────┐
│ Scenario                        │ EBS (RWO)  │ StatefulSet │ EFS (RWX)   │
│                                 │ + Deploy   │ + EBS       │ + Deploy    │
├─────────────────────────────────┼────────────┼─────────────┼─────────────┤
│ 3 replicas share same data?     │ NO (fails) │ NO (each    │ YES         │
│                                 │            │  gets own)  │             │
├─────────────────────────────────┼────────────┼─────────────┼─────────────┤
│ 3 replicas, each needs own DB?  │ NO         │ YES         │ Not ideal   │
├─────────────────────────────────┼────────────┼─────────────┼─────────────┤
│ Use case                        │ Single pod │ Databases   │ Shared      │
│                                 │ only       │ (MySQL,     │ files (CMS, │
│                                 │            │  Mongo,     │  uploads,   │
│                                 │            │  Kafka)     │  ML data)   │
└─────────────────────────────────┴────────────┴─────────────┴─────────────┘
```

---

### Pod Rescheduled to Another Node — What Happens to EBS?

```
QUESTION: If a pod is deleted/crashes and gets scheduled on a DIFFERENT node,
          can it still use the old EBS volume?

ANSWER: YES! But only if the new node is in the SAME Availability Zone (AZ).
```

#### How EBS Reattachment Works

```
Step 1: Pod dies on Node-1 (in AZ ap-south-1a)

  ┌──── Node 1 (AZ: ap-south-1a) ────┐
  │                                    │
  │  Pod (DELETED / CRASHED)           │
  │    ↓                               │
  │  [EBS Volume: vol-abc123]          │
  │   Status: attached → detaching...  │
  │                                    │
  └────────────────────────────────────┘

Step 2: Kubernetes scheduler picks Node-2 (SAME AZ: ap-south-1a)

  ┌──── Node 2 (AZ: ap-south-1a) ────┐
  │                                    │
  │  New Pod (Pending → Running)       │
  │    ↓                               │
  │  [EBS Volume: vol-abc123]          │
  │   Status: attaching → attached     │
  │                                    │
  └────────────────────────────────────┘

  The SAME EBS volume (vol-abc123) detaches from Node-1 and
  reattaches to Node-2. ALL DATA IS PRESERVED!

  Time: ~30-60 seconds for detach + reattach
```

#### But What If the New Node Is in a DIFFERENT AZ?

```
EBS volumes are AZ-locked! They CANNOT move across AZs.

  ┌──── Node 1 (AZ: ap-south-1a) ────┐
  │  Pod (DELETED)                     │
  │  [EBS: vol-abc123]                 │
  │   → This EBS ONLY exists in 1a!   │
  └────────────────────────────────────┘

  ┌──── Node 3 (AZ: ap-south-1b) ────┐
  │  New Pod (STUCK!)                  │
  │  Cannot attach vol-abc123          │
  │  because it's in a different AZ!   │
  │                                    │
  │  Error: "volume is in AZ 1a but   │
  │   node is in AZ 1b"               │
  └────────────────────────────────────┘
```

#### How to Prevent Cross-AZ Issues

```
This is EXACTLY why WaitForFirstConsumer is important!

volumeBindingMode: WaitForFirstConsumer

What it does:
  1. PVC is created → EBS is NOT created yet (Pending)
  2. Pod is scheduled to Node-2 in ap-south-1a
  3. NOW EBS is created in ap-south-1a (same AZ as the node)
  4. If pod restarts, scheduler PREFERS nodes in ap-south-1a
     (because that's where the EBS volume exists)

Without WaitForFirstConsumer (using "Immediate" binding):
  1. PVC is created → EBS is immediately created in random AZ (say 1b)
  2. Pod is scheduled to Node in 1a → FAILS! Volume is in 1b!

ALWAYS use WaitForFirstConsumer for EBS StorageClass!
```

#### EBS Reattachment Flow (Complete Picture)

```
Pod deleted → Deployment creates new pod → Scheduler checks:
  │
  ├─ "This pod needs PVC mysql-ebs-pvc"
  ├─ "PVC is bound to PV pvc-abc123"
  ├─ "PV pvc-abc123 is an EBS volume in AZ ap-south-1a"
  ├─ "I must schedule this pod on a node in ap-south-1a"
  │
  ├─ Finds Node in ap-south-1a → Schedule pod there
  │    → EBS CSI driver detaches from old node
  │    → EBS CSI driver attaches to new node
  │    → Pod starts with ALL old data intact
  │    → Downtime: ~30-60 seconds
  │
  └─ No healthy node in ap-south-1a? → Pod stays Pending!
       (This is why multi-AZ node groups are important)
```

---

### Dynamic Provisioning Clean Up

```bash
kubectl delete deployment mysql
kubectl delete secret mysql-secret
kubectl delete pvc mysql-ebs-pvc    # ← This also deletes the EBS volume (reclaimPolicy: Delete)
kubectl delete sc ebs-gp3
```

### Static vs Dynamic — When to Use What

```
┌───────────────────────────┬──────────────────────────────────────────┐
│ Use Static When           │ Use Dynamic When                         │
├───────────────────────────┼──────────────────────────────────────────┤
│ Migrating existing EBS    │ New apps (most of the time)              │
│ volumes to K8s            │                                          │
│                           │                                          │
│ You need a specific       │ You want K8s to handle                   │
│ pre-created volume        │ everything automatically                 │
│                           │                                          │
│ Compliance requires       │ Auto-scaling / CI-CD                     │
│ pre-approved volumes      │ environments                             │
│                           │                                          │
│ Learning how PV/PVC       │ Production workloads                     │
│ binding works             │ (recommended)                            │
└───────────────────────────┴──────────────────────────────────────────┘

In interviews:
  "What is the difference between static and dynamic provisioning?"

  Static  = Admin creates EBS + PV manually, then PVC binds to it
  Dynamic = PVC requests storage via StorageClass, CSI driver creates
            EBS + PV automatically
```

---

## Part 2: EFS Volumes on EKS (Shared Storage)

### Why EFS?

```
EBS problem:
  Pod-A on Node-1 writes a file → Pod-B on Node-2 can't see it!
  Because EBS is attached to ONE node only.

EFS solution:
  Pod-A on Node-1 writes a file → Pod-B on Node-2 sees it INSTANTLY!
  Because EFS is a shared network filesystem.

Use cases:
  - WordPress uploads (multiple pods serve the same images)
  - Shared config files
  - Machine learning datasets
  - Any app where multiple pods need the SAME files
```

### Prerequisites

```bash
# 1. Install EFS CSI Driver
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system

# OR via EKS add-on:
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-efs-csi-driver

# 2. Verify
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
```

### Step 1: Create an EFS Filesystem in AWS

```bash
# Create EFS filesystem
aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value=eks-efs \
  --region ap-south-1

# Note the FileSystemId from the output (e.g., fs-0123456789abcdef0)

# Create mount targets in each subnet where your EKS nodes run
# Get your VPC and subnet IDs:
aws eks describe-cluster --name my-cluster --query "cluster.resourcesVpcConfig" --output json

# Create mount targets (one per subnet/AZ):
aws efs create-mount-target \
  --file-system-id fs-0123456789abcdef0 \
  --subnet-id subnet-xxxxxxxxx \
  --security-groups sg-xxxxxxxxx

# The security group must allow inbound NFS (port 2049) from your EKS nodes
```

### Step 2: Create StorageClass for EFS

```yaml
# efs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com         # ← AWS EFS CSI driver
parameters:
  provisioningMode: efs-ap           # ← EFS Access Point mode
  fileSystemId: fs-0123456789abcdef0 # ← Replace with YOUR EFS ID!
  directoryPerms: "700"
  basePath: "/dynamic_provisioning"
reclaimPolicy: Delete
```

```bash
kubectl apply -f efs-storageclass.yaml
```

### Step 3: Create PVC with ReadWriteMany

```yaml
# efs-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-efs-pvc
spec:
  accessModes:
    - ReadWriteMany                  # ← Multiple pods can read AND write!
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi                   # ← EFS is elastic, this is just a label
```

```bash
kubectl apply -f efs-pvc.yaml

kubectl get pvc shared-efs-pvc
# NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# shared-efs-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWX            efs-sc         10s
```

### Step 4: Multiple Pods Sharing EFS

```yaml
# efs-shared-pods.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: writer-app
spec:
  replicas: 2                        # ← 2 writers on different nodes
  selector:
    matchLabels:
      app: writer
  template:
    metadata:
      labels:
        app: writer
    spec:
      containers:
      - name: writer
        image: busybox
        command: ["sh", "-c"]
        args:
        - |
          while true; do
            echo "$(hostname) wrote at $(date)" >> /shared/log.txt
            sleep 5
          done
        volumeMounts:
        - name: shared-data
          mountPath: /shared
      volumes:
      - name: shared-data
        persistentVolumeClaim:
          claimName: shared-efs-pvc  # ← Same PVC!
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reader-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reader
  template:
    metadata:
      labels:
        app: reader
    spec:
      containers:
      - name: reader
        image: busybox
        command: ["sh", "-c"]
        args:
        - |
          while true; do
            echo "=== Shared log contents ==="
            tail -5 /shared/log.txt
            echo ""
            sleep 5
          done
        volumeMounts:
        - name: shared-data
          mountPath: /shared
      volumes:
      - name: shared-data
        persistentVolumeClaim:
          claimName: shared-efs-pvc  # ← Same PVC shared across deployments!
```

```bash
kubectl apply -f efs-shared-pods.yaml

# Check reader logs - it sees writes from BOTH writer pods!
kubectl logs -l app=reader --tail=10
# === Shared log contents ===
# writer-app-xxxxxx-xxxxx wrote at Thu Jan 15 10:30:00 UTC 2025
# writer-app-xxxxxx-yyyyy wrote at Thu Jan 15 10:30:02 UTC 2025
# writer-app-xxxxxx-xxxxx wrote at Thu Jan 15 10:30:05 UTC 2025
# writer-app-xxxxxx-yyyyy wrote at Thu Jan 15 10:30:07 UTC 2025
```

Both writer pods (possibly on different nodes) write to the same EFS, and the reader pod sees everything.

### Clean Up

```bash
kubectl delete deployment writer-app reader-app
kubectl delete pvc shared-efs-pvc
kubectl delete sc efs-sc
# Don't forget to delete the EFS filesystem in AWS if no longer needed:
# aws efs delete-file-system --file-system-id fs-0123456789abcdef0
```

---

## EBS vs EFS - Full Comparison

| Feature | EBS (gp3) | EFS |
|---------|-----------|-----|
| **Type** | Block storage (like a hard disk) | File storage (like NFS) |
| **Access mode** | ReadWriteOnce (1 node) | ReadWriteMany (multiple nodes) |
| **Multi-pod** | No (1 pod at a time) | Yes (100s of pods) |
| **Multi-AZ** | No (single AZ) | Yes (automatically) |
| **Performance** | Very high (up to 64K IOPS) | Good (scales with usage) |
| **Cost** | ~$0.08/GB/month (gp3) | ~$0.30/GB/month |
| **Size** | Fixed (you set 20Gi, you pay for 20Gi) | Elastic (pay for what you use) |
| **Resize** | Yes (increase only) | Automatic (grows as needed) |
| **Encryption** | Yes (at rest + in transit) | Yes (at rest + in transit) |
| **Snapshots** | Yes | No (use AWS Backup) |
| **Best for** | Databases, single-pod apps | Shared files, CMS, ML data |
| **CSI Driver** | aws-ebs-csi-driver | aws-efs-csi-driver |

---

## Cost Estimation

```
Example: 100GB storage for 1 month

EBS gp3:   100GB × $0.08  = $8/month
EFS:       100GB × $0.30  = $30/month
EFS-IA:    100GB × $0.025 = $2.50/month  (Infrequent Access - for cold data)

TIP: Use EFS Intelligent-Tiering to auto-move cold files to EFS-IA
     → saves 60-70% on storage costs!
```

---

## Key Takeaways

1. **Never use hostPath in production** - data is tied to one node
2. **EBS** = block storage, one pod at a time, best for databases
3. **EFS** = shared file storage, many pods can read/write simultaneously
4. **Always use gp3** over gp2 for EBS - better performance, same price
5. **Install the CSI Driver** first (EBS or EFS) - K8s doesn't know about AWS storage by default
6. **WaitForFirstConsumer** binding mode ensures EBS is created in the same AZ as your pod
7. **allowVolumeExpansion: true** lets you resize EBS volumes later
8. **EFS costs 4x more than EBS** per GB - only use EFS when you need shared access
9. **Always encrypt** your volumes (`encrypted: "true"` in StorageClass)
10. **EFS is elastic** - you don't need to specify size upfront, it grows automatically
11. **EBS + Deployment with multiple replicas = FAILS** - use StatefulSet (each replica gets own EBS) or switch to EFS (shared storage)
12. **EBS survives pod restarts** - if pod moves to another node in the SAME AZ, EBS detaches and reattaches automatically (~30-60 sec)
13. **EBS CANNOT cross AZs** - if no healthy node exists in the EBS volume's AZ, pod stays Pending
14. **Static provisioning** = you create EBS + PV manually (for existing volumes, migration). **Dynamic provisioning** = StorageClass + PVC, K8s creates EBS automatically (recommended for production)

---

**Back to:** [Volumes Theory](../notes.md) | **Related:** [NFS Volumes (On-Prem)](../nfs-volumes/notes.md) | [Volumes Demo (Local)](../../day13-volumes-demo/notes.md)
