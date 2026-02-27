# Day 12 - Volumes & Persistent Storage

## The Problem - Pods Lose Data!

By default, containers have an **ephemeral (temporary) filesystem**. When a pod dies or restarts, **all data inside the container is lost**.

```
Pod starts          Pod crashes         New Pod starts
┌──────────┐        ┌──────────┐        ┌──────────┐
│ Container │        │ Container│        │ Container │
│           │        │  CRASH!  │        │           │
│ data.txt  │  ───►  │    X     │  ───►  │ (empty!)  │
│ logs/     │        │    X     │        │           │
└──────────┘        └──────────┘        └──────────┘
   Has data          Data gone!          Fresh start
                                         No old data
```

### Why does this happen?

Each container gets its own **writable layer** from the container image. This layer is:
- **Temporary** - tied to the container's lifecycle
- **Isolated** - other containers can't see it
- **Gone when container stops** - like RAM, not like a hard disk

### Real-world examples where this is a problem

| Use Case | What Happens Without Volumes |
|----------|------------------------------|
| Database (MySQL, PostgreSQL) | All database records are lost on restart |
| File uploads | User-uploaded files disappear |
| Application logs | Logs vanish when pod restarts |
| Shared data between containers | Sidecar containers can't share files |
| Cache (Redis) | Cache rebuilds from scratch every time |

**Solution:** Kubernetes **Volumes** - attach storage to pods that survives container restarts.

---

## Volume Types Overview

Kubernetes supports many volume types. Here are the most important ones:

```
Volume Types (from simple to production-ready)
│
├── emptyDir        ← Temporary shared storage (dies with pod)
├── hostPath        ← Uses the node's filesystem (good for testing)
│
├── PersistentVolume (PV)    ← Cluster-level storage resource
├── PersistentVolumeClaim (PVC) ← Pod's request for storage
│
└── Cloud Provider Volumes
    ├── awsElasticBlockStore (EBS)
    ├── gcePersistentDisk
    └── azureDisk
```

---

## 1. emptyDir - Temporary Shared Storage

An `emptyDir` volume is created when a pod is assigned to a node. It starts **empty** and is **deleted when the pod is removed** from the node.

### When to use emptyDir

- Sharing files between containers in the **same pod**
- Temporary scratch space (e.g., sorting large data)
- Caching

```
┌───────── Pod ─────────────────────┐
│                                    │
│  ┌── Container A ──┐              │
│  │  writes to      │──┐           │
│  │  /shared/data   │  │           │
│  └─────────────────┘  │           │
│                        ▼           │
│              ┌─── emptyDir ───┐   │
│              │  (shared disk) │   │
│              └────────────────┘   │
│                        ▲           │
│  ┌── Container B ──┐  │           │
│  │  reads from     │──┘           │
│  │  /shared/data   │              │
│  └─────────────────┘              │
│                                    │
└────────────────────────────────────┘
```

### YAML Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: shared-pod
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'Hello from writer' > /shared/data.txt && sleep 3600"]
    volumeMounts:
    - name: shared-vol          # ← Mount the volume
      mountPath: /shared        # ← Where inside the container

  - name: reader
    image: busybox
    command: ["sh", "-c", "sleep 5 && cat /shared/data.txt && sleep 3600"]
    volumeMounts:
    - name: shared-vol          # ← Same volume name
      mountPath: /shared        # ← Can use same or different path

  volumes:                       # ← Define volumes at pod level
  - name: shared-vol
    emptyDir: {}                 # ← Empty directory, created fresh
```

**Key point:** `emptyDir` is deleted when the **pod** is deleted (not just when a container restarts).

---

## 2. hostPath - Use the Node's Filesystem

A `hostPath` volume mounts a file or directory from the **host node's filesystem** into your pod.

```
┌──── Worker Node ────────────────────┐
│                                      │
│  Node filesystem:                    │
│  /data/myapp/  ◄──── hostPath        │
│       │                              │
│       ▼                              │
│  ┌──── Pod ────────┐                │
│  │  Container      │                │
│  │  /app/data ─────┼── mounted      │
│  └─────────────────┘                │
│                                      │
└──────────────────────────────────────┘
```

### YAML Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-pod
spec:
  containers:
  - name: myapp
    image: nginx
    volumeMounts:
    - name: host-data
      mountPath: /usr/share/nginx/html   # ← Inside the container
  volumes:
  - name: host-data
    hostPath:
      path: /data/nginx                  # ← Path on the node
      type: DirectoryOrCreate            # ← Create if doesn't exist
```

### hostPath types

| Type | Description |
|------|-------------|
| `""` | No checks (default) |
| `DirectoryOrCreate` | Create directory if it doesn't exist |
| `Directory` | Directory must already exist |
| `FileOrCreate` | Create file if it doesn't exist |
| `File` | File must already exist |

### Warning about hostPath

```
⚠️  hostPath problems:
├── Pod is tied to a specific node (data is on THAT node only)
├── If pod moves to another node, it can't find its data
├── Security risk (pod can access host filesystem)
└── NOT recommended for production - use PersistentVolumes instead
```

---

## Local Persistent Volumes (Production Alternative to hostPath)

hostPath is bad for production, but sometimes you WANT to use the node's local disk (NVMe/SSD) for **high-performance** workloads. That's where **Local PV** comes in.

### hostPath vs Local PV

```
hostPath:
  ❌ No scheduling awareness (pod can land on wrong node)
  ❌ No capacity tracking
  ❌ Security risk
  ❌ Not supported by many storage features

Local PV:
  ✅ K8s ensures pod is scheduled on the node where the disk is
  ✅ Proper PV/PVC lifecycle
  ✅ Capacity tracking
  ✅ Works with StatefulSets
  ✅ Production-grade

Both store data on the LOCAL node disk (not network storage)
Both lose data if the NODE dies
```

### When to Use Local PV

```
Use Local PV when:
  - You need very high disk I/O (NVMe SSDs)
  - Network latency is unacceptable (databases like Cassandra, Kafka, Elasticsearch)
  - You have dedicated storage nodes

Do NOT use Local PV when:
  - You need data to survive node failure → use EBS, EFS, NFS instead
  - You need shared access across nodes → use EFS or NFS
  - Your pods need to move freely between nodes
```

### Local PV YAML

```yaml
# local-pv.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner   # ← No dynamic provisioning
volumeBindingMode: WaitForFirstConsumer     # ← Wait until pod is scheduled
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/disks/ssd1                   # ← Actual disk path on the node
  nodeAffinity:                             # ← REQUIRED for local PV!
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - worker-node-1                   # ← Only this node has the disk
```

```
Key difference from hostPath:
  hostPath:  Pod lands on any node → might not find the data
  Local PV:  nodeAffinity + WaitForFirstConsumer
             → K8s GUARANTEES pod runs on the right node
```

### Local PV vs Network Storage

| Feature | Local PV | EBS/NFS/EFS |
|---------|----------|-------------|
| **Performance** | Highest (direct disk) | Good (network hop) |
| **Survives node failure** | No | Yes |
| **Pod scheduling** | Tied to node | Flexible |
| **Use case** | High-IOPS databases | General purpose |
| **Dynamic provisioning** | No (manual PV per disk) | Yes |

> **For production storage guides:** See [AWS Volumes (EBS/EFS)](aws-volumes/notes.md) | [NFS Volumes (On-Prem)](nfs-volumes/notes.md)

---

## 3. PersistentVolume (PV) and PersistentVolumeClaim (PVC)

This is the **production way** to handle storage in Kubernetes. It separates the "storage setup" from the "storage usage".

### Why PV/PVC?

Think of it like renting an apartment:

```
Real World Analogy:
├── Apartment (PV)       = The actual storage that exists
├── Lease Agreement (PVC) = Your request to use storage
├── Landlord (Admin)     = Creates the PV (provisions storage)
└── Tenant (Developer)   = Creates a PVC to claim storage

Kubernetes:
├── PersistentVolume (PV)      = A piece of storage in the cluster
├── PersistentVolumeClaim (PVC) = A request for storage by a user
├── Cluster Admin              = Creates PVs
└── Developer                  = Creates PVCs, uses them in Pods
```

### The Big Picture

```
┌─── Cluster Admin ───┐      ┌─── Developer ───────────────────┐
│                      │      │                                  │
│  Creates PV:         │      │  1. Creates PVC:                │
│  "10Gi of SSD on     │      │     "I need 5Gi of storage"     │
│   AWS EBS"           │      │                                  │
│                      │      │  2. Uses PVC in Pod:             │
│  ┌────────────┐      │      │     volumeMounts:                │
│  │     PV     │◄─────┼──────┼──── PVC ──── Pod                │
│  │   10Gi     │ bind  │      │                                  │
│  │   SSD      │      │      │  Developer never needs to know   │
│  └────────────┘      │      │  WHERE the storage actually is   │
│                      │      │                                  │
└──────────────────────┘      └──────────────────────────────────┘
```

### PersistentVolume (PV) - The Actual Storage

A PV is a **cluster-level resource** (not namespaced). It represents a piece of physical storage.

```yaml
# pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 10Gi                    # ← How much storage
  accessModes:
    - ReadWriteOnce                  # ← Who can access it
  persistentVolumeReclaimPolicy: Retain   # ← What happens when PVC is deleted
  storageClassName: manual           # ← Grouping label
  hostPath:                          # ← Where the data actually lives
    path: /mnt/data                  #    (hostPath for demo, use cloud volumes in prod)
```

### PersistentVolumeClaim (PVC) - Request for Storage

A PVC is a **namespaced resource**. It's how pods request storage.

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce                  # ← Must match PV's access mode
  resources:
    requests:
      storage: 5Gi                   # ← How much you need (must be <= PV)
  storageClassName: manual           # ← Must match PV's storageClassName
```

### Using PVC in a Pod

```yaml
# pod-with-pvc.yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: nginx
    volumeMounts:
    - name: my-storage
      mountPath: /usr/share/nginx/html   # ← Mount point inside container
  volumes:
  - name: my-storage
    persistentVolumeClaim:
      claimName: my-pvc                  # ← Reference the PVC (not the PV!)
```

### How PV and PVC Bind Together

```
1. Admin creates PV (10Gi, ReadWriteOnce, storageClass=manual)
2. Developer creates PVC (5Gi, ReadWriteOnce, storageClass=manual)
3. Kubernetes BINDS PVC to PV automatically (if compatible)
4. Developer creates Pod referencing the PVC
5. Pod gets the storage!

PV States:
┌───────────┐     ┌───────────┐     ┌───────────┐     ┌───────────┐
│ Available  │────►│   Bound   │────►│ Released  │────►│  Failed   │
│ (no PVC)   │     │ (has PVC) │     │(PVC gone) │     │  (error)  │
└───────────┘     └───────────┘     └───────────┘     └───────────┘
```

---

## Access Modes

Access modes define **how** the volume can be mounted:

| Access Mode | Short | Description | Use Case |
|-------------|-------|-------------|----------|
| `ReadWriteOnce` | RWO | Read-write by a **single node** | Databases (MySQL, PostgreSQL) |
| `ReadOnlyMany` | ROX | Read-only by **many nodes** | Shared config files, static assets |
| `ReadWriteMany` | RWX | Read-write by **many nodes** | Shared file uploads, NFS |
| `ReadWriteOncePod` | RWOP | Read-write by a **single pod** | Strict single-writer (K8s 1.22+) |

```
ReadWriteOnce (RWO):          ReadWriteMany (RWX):
┌────────┐                    ┌────────┐  ┌────────┐  ┌────────┐
│ Node 1 │                    │ Node 1 │  │ Node 2 │  │ Node 3 │
│ ┌────┐ │                    │ ┌────┐ │  │ ┌────┐ │  │ ┌────┐ │
│ │Pod │ │  ← Only this       │ │Pod │ │  │ │Pod │ │  │ │Pod │ │
│ └──┬─┘ │    node can        │ └──┬─┘ │  │ └──┬─┘ │  │ └──┬─┘ │
│    │    │    mount           │    │    │  │    │    │  │    │    │
│  ┌─▼──┐│                    │    │    │  │    │    │  │    │    │
│  │ PV ││                    └────┼────┘  └────┼────┘  └────┼────┘
│  └────┘│                         │            │            │
└────────┘                         └────────┬───┘────────────┘
                                            │
                                         ┌──▼──┐
                                         │ PV  │ (e.g., NFS, EFS)
                                         └─────┘
```

**Important:** Most cloud block storage (EBS, Azure Disk) only supports **RWO**. For RWX, use file storage like NFS, AWS EFS, or Azure Files.

---

## Reclaim Policies

What happens to the PV **after the PVC is deleted**?

| Policy | Description | Use Case |
|--------|-------------|----------|
| `Retain` | PV and data are **kept**. Admin must manually clean up. | Production data you can't afford to lose |
| `Delete` | PV and underlying storage are **deleted automatically** | Temporary/development environments |
| `Recycle` | Data is deleted (`rm -rf /volume/*`), PV becomes Available again | **Deprecated** - use dynamic provisioning instead |

```
PVC Deleted - What happens to PV?

Retain:                    Delete:
┌──────────┐              ┌──────────┐
│    PV    │              │    PV    │
│  Status: │              │          │
│ Released │              │  DELETED │
│          │              │          │
│ Data is  │              │ Data is  │
│ KEPT     │              │ GONE     │
│          │              │          │
│ Admin    │              │ Cloud    │
│ cleans   │              │ disk     │
│ up later │              │ removed  │
└──────────┘              └──────────┘
```

---

## StorageClass - Dynamic Provisioning

So far, we've been **statically provisioning** storage: an admin creates a PV first, then the developer creates a PVC.

**Dynamic provisioning** creates the PV **automatically** when a PVC is created!

### Static vs Dynamic Provisioning

```
STATIC Provisioning (Manual):
1. Admin creates PV           ┌──────┐
2. Developer creates PVC  ──► │  PV  │ (already exists)
3. PVC binds to PV            └──────┘

DYNAMIC Provisioning (Automatic):
1. Admin creates StorageClass
2. Developer creates PVC  ──► StorageClass ──► Creates PV automatically!
                                                ┌──────┐
                                                │  PV  │ (auto-created)
                                                └──────┘
```

### StorageClass YAML

```yaml
# storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs    # ← Who creates the storage
parameters:
  type: gp3                           # ← AWS EBS volume type
  fsType: ext4                        # ← Filesystem type
reclaimPolicy: Delete                 # ← Delete PV when PVC is deleted
volumeBindingMode: WaitForFirstConsumer  # ← Wait until pod is scheduled
allowVolumeExpansion: true            # ← Allow resizing
```

### Using a StorageClass in PVC

```yaml
# pvc-dynamic.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-dynamic-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: fast-ssd          # ← Reference the StorageClass
                                      #    PV is created AUTOMATICALLY!
```

### Common StorageClass Provisioners

| Cloud | Provisioner | Volume Type |
|-------|-------------|-------------|
| AWS | `ebs.csi.aws.com` | EBS (gp2, gp3, io1) |
| GCP | `pd.csi.storage.gke.io` | Persistent Disk |
| Azure | `disk.csi.azure.com` | Azure Disk |
| Local | `kubernetes.io/no-provisioner` | Local storage |
| NFS | Various CSI drivers | NFS shares |

### Checking StorageClasses

```bash
# List available StorageClasses
kubectl get storageclass
# NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE
# standard (default)   k8s.io/minikube-hostpath   Delete          Immediate
# fast-ssd             ebs.csi.aws.com            Delete          WaitForFirstConsumer

# See details
kubectl describe storageclass standard
```

**Note:** Minikube comes with a `standard` StorageClass by default that uses `hostPath` storage.

---

## Putting It All Together - The Full Flow

```
┌──────────────────────────────────────────────────────────────┐
│                   The Storage Flow                            │
│                                                              │
│  Developer                  Kubernetes              Storage  │
│                                                              │
│  1. Create PVC ──────►  2. Find matching PV                 │
│     (5Gi, RWO)             or StorageClass                   │
│                                   │                          │
│                                   ▼                          │
│                          3. Bind PVC to PV ────► 4. Actual   │
│                             (or create PV        Disk/Volume │
│                              dynamically)                    │
│                                   │                          │
│  5. Create Pod ──────►  6. Mount volume                     │
│     with PVC ref           into container                    │
│                                   │                          │
│  7. App reads/writes      8. Data persists                   │
│     to mountPath             even if pod                     │
│                              restarts!                       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Quick Reference - Useful kubectl Commands

```bash
# PersistentVolumes (cluster-wide)
kubectl get pv
kubectl describe pv <pv-name>
kubectl delete pv <pv-name>

# PersistentVolumeClaims (namespaced)
kubectl get pvc
kubectl describe pvc <pvc-name>
kubectl delete pvc <pvc-name>

# StorageClasses
kubectl get storageclass    # or: kubectl get sc
kubectl describe sc <name>

# Check which PVC is bound to which PV
kubectl get pv,pvc

# See volume mounts in a pod
kubectl describe pod <pod-name> | grep -A 5 "Mounts"
kubectl describe pod <pod-name> | grep -A 5 "Volumes"
```

---

## Key Takeaways

1. **Containers are ephemeral** - data is lost when a pod dies, unless you use volumes
2. **emptyDir** = temporary shared storage between containers in the same pod (dies with the pod)
3. **hostPath** = use the node's filesystem (testing only, not for production)
4. **PersistentVolume (PV)** = a piece of storage provisioned in the cluster (cluster-level resource)
5. **PersistentVolumeClaim (PVC)** = a request for storage by a developer (namespaced resource)
6. **StorageClass** = enables dynamic provisioning (PV created automatically when PVC is created)
7. **Access Modes** = RWO (single node), ROX (read-only many), RWX (read-write many)
8. **Reclaim Policies** = Retain (keep data), Delete (remove data), Recycle (deprecated)
9. Developers only need to know about **PVC** and **StorageClass** - they never touch PVs directly
10. Always use **dynamic provisioning** with StorageClass in production

---

## Practice / Homework

1. Create a pod with `emptyDir` volume shared between two containers
2. Create a PV (5Gi, RWO, hostPath) and a matching PVC (3Gi)
3. Verify they bind: `kubectl get pv,pvc`
4. Create a pod that uses the PVC and writes data
5. Delete the pod and recreate it - verify data persists!
6. Check what StorageClasses are available: `kubectl get sc`
7. Create a PVC using the default StorageClass (no PV needed - it's dynamic!)
8. Experiment with different access modes and reclaim policies

---

**Previous:** [← Day 11 - Amazon EKS](../day11-eks/notes.md)
**Next:** [Day 13 - Volumes Demo →](../day13-volumes-demo/notes.md)
