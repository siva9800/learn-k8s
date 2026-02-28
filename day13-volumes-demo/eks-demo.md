# Day 13 - Volumes Demo (EKS / Production)

> **Pre-requisite:** Read [AWS Volumes Theory (EBS & EFS)](../day12-volumes/aws-volumes/notes.md) before this demo.
> **Local demos:** See [Volumes Demo (Local / Minikube)](notes.md) for emptyDir, hostPath, Local PV demos.

These demos run on an **EKS cluster** with real AWS storage (EBS & EFS). Everything here is production-grade.

```
What you need before starting:
  - EKS cluster running (eksctl or Terraform)
  - kubectl configured to your EKS cluster
  - AWS CLI configured
  - EBS CSI Driver installed (setup below)
  - EFS CSI Driver installed (setup below, for EFS demos only)
```

---

## Setup: EBS CSI Driver Installation on EKS

```
Why do we need this?

  Kubernetes doesn't know how to create/attach AWS EBS volumes by default.
  The EBS CSI (Container Storage Interface) Driver is a plugin that tells
  Kubernetes: "Here's how to talk to AWS EBS."

  Without it:
    kubectl apply -f pvc.yaml → "no volume plugin matched" → PVC stuck in Pending!

  With it:
    kubectl apply -f pvc.yaml → CSI driver calls AWS API → EBS created → PVC Bound!
```

### Step 1: Create IAM Role for the EBS CSI Driver

```
The CSI driver runs as pods inside your cluster. Those pods need AWS permissions
to create/delete/attach EBS volumes. We give them permissions using IRSA
(IAM Role for Service Account).

Flow:
  Create IAM Role  →  Attach EBS policy  →  Link to K8s ServiceAccount  →  CSI driver pods use it

This is more secure than giving permissions to the entire node!
```

```bash
# First, check if your cluster has an OIDC provider (required for IRSA)
aws eks describe-cluster --name my-cluster \
  --query "cluster.identity.oidc.issuer" --output text
# https://oidc.eks.ap-south-1.amazonaws.com/id/XXXXXXXXXXXXXXXX

# If you see a URL → OIDC is already set up. If empty, create one:
eksctl utils associate-iam-oidc-provider \
  --cluster my-cluster \
  --region ap-south-1 \
  --approve

# Create the IAM Service Account with EBS permissions
eksctl create iamserviceaccount \
  --cluster my-cluster \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve \
  --region ap-south-1

# Verify the service account was created
kubectl get sa ebs-csi-controller-sa -n kube-system
# NAME                     SECRETS   AGE
# ebs-csi-controller-sa    0         30s

# Check the IAM role ARN attached to it
kubectl describe sa ebs-csi-controller-sa -n kube-system | grep role-arn
# eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eksctl-my-cluster-addon-...
```

```
What permissions does this give?
  - ec2:CreateVolume        → Create new EBS volumes
  - ec2:DeleteVolume        → Delete EBS volumes
  - ec2:AttachVolume        → Attach EBS to EC2 instances (nodes)
  - ec2:DetachVolume        → Detach EBS from EC2 instances
  - ec2:CreateSnapshot      → Create volume snapshots
  - ec2:ModifyVolume        → Resize volumes
  - ec2:DescribeVolumes     → List/check volume status
```

### Step 2: Install the EBS CSI Driver

```bash
# Method 1: Install as EKS Add-on (Recommended)
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::123456789012:role/eksctl-my-cluster-addon-ebs-csi-... \
  --region ap-south-1

# OR using eksctl:
eksctl create addon \
  --cluster my-cluster \
  --name aws-ebs-csi-driver \
  --region ap-south-1

# Method 2: Install via Helm (alternative)
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa
```

### Step 3: Verify the Driver is Running

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
# NAME                                  READY   STATUS    RESTARTS   AGE
# ebs-csi-controller-xxxxxxxxx-xxxxx    6/6     Running   0          2m
# ebs-csi-controller-xxxxxxxxx-yyyyy    6/6     Running   0          2m
# ebs-csi-node-aaaaa                    3/3     Running   0          2m
# ebs-csi-node-bbbbb                    3/3     Running   0          2m

# Controller pods: handle create/delete/attach/detach (runs on any node)
# Node pods: one per node (DaemonSet), handles mounting volumes on that node

# Check CSI driver is registered
kubectl get csidriver
# NAME              ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   AGE
# ebs.csi.aws.com   true             false            false             2m
```

```
If pods are NOT running, check:
  1. IAM role is correct:
     kubectl describe sa ebs-csi-controller-sa -n kube-system
  2. Pods have errors:
     kubectl logs -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
  3. Node IAM role has basic EC2 permissions
```

### Quick Test: Is EBS CSI Working?

```bash
# Create a quick test PVC
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-test
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ebs-test
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: ebs-test-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c", "echo 'EBS CSI works!' > /data/test.txt && cat /data/test.txt && sleep 60"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ebs-test-pvc
EOF

# Wait and check
kubectl get pod ebs-test-pod -w
# STATUS: ContainerCreating → Running

kubectl logs ebs-test-pod
# EBS CSI works!

# Clean up test
kubectl delete pod ebs-test-pod
kubectl delete pvc ebs-test-pvc
kubectl delete sc ebs-test

echo "EBS CSI Driver is working! Ready for demos."
```

---

## Setup: EFS CSI Driver Installation (For Demo 4)

```
Only needed if you want to do the EFS (shared storage) demo.
Skip this if you only need EBS.
```

```bash
# Create IAM Service Account for EFS
eksctl create iamserviceaccount \
  --cluster my-cluster \
  --namespace kube-system \
  --name efs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
  --approve \
  --region ap-south-1

# Install EFS CSI Driver as EKS Add-on
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-efs-csi-driver \
  --region ap-south-1

# OR via Helm:
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system

# Verify
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver
# NAME                                  READY   STATUS    RESTARTS   AGE
# efs-csi-controller-xxxxxxxxx-xxxxx    3/3     Running   0          1m
# efs-csi-node-aaaaa                    3/3     Running   0          1m
# efs-csi-node-bbbbb                    3/3     Running   0          1m
```

---

## Demo 1 - EBS Static Provisioning (Manual)

**Goal:** Manually create an EBS volume in AWS, then use it in Kubernetes. Understand the full PV → PVC → Pod flow.

```
Flow:
  AWS Console / CLI          Kubernetes
  ================          ==========
  Create EBS volume    →    Create PV (pointing to EBS ID)
                            Create PVC (binds to PV)
                            Create Pod (uses PVC)
```

### Step 1: Create EBS Volume in AWS

```bash
# First, find which AZ your nodes are in
kubectl get nodes -o wide
# NAME                                           STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE         KERNEL-VERSION                  CONTAINER-RUNTIME
# ip-192-168-1-100.ap-south-1.compute.internal   Ready    <none>   2d    v1.28.3   192.168.1.100   <none>      Amazon Linux 2   5.10.205-195.807.amzn2.x86_64   containerd://1.7.2

# Check which AZ each node is in
kubectl get nodes --label-columns topology.kubernetes.io/zone
# NAME                                           STATUS   ROLES    AGE   ZONE
# ip-192-168-1-100.ap-south-1.compute.internal   Ready    <none>   2d    ap-south-1a
# ip-192-168-2-200.ap-south-1.compute.internal   Ready    <none>   2d    ap-south-1b

# Create EBS volume in ap-south-1a (same AZ as one of your nodes!)
aws ec2 create-volume \
  --availability-zone ap-south-1a \
  --size 10 \
  --volume-type gp3 \
  --encrypted \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=k8s-static-demo}]' \
  --region ap-south-1

# Output:
# {
#     "VolumeId": "vol-0abc123def456789",    ← COPY THIS!
#     "Size": 10,
#     "VolumeType": "gp3",
#     "AvailabilityZone": "ap-south-1a"
# }

# Verify it's available
aws ec2 describe-volumes --volume-ids vol-0abc123def456789 \
  --query "Volumes[0].State" --output text
# available
```

### Step 2: Create PV, PVC, and Pod

```yaml
# static-ebs-demo.yaml

# --- PersistentVolume ---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-ebs-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""                         # ← Empty for static provisioning
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-0abc123def456789         # ← Replace with YOUR volume ID!
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.ebs.csi.aws.com/zone
          operator: In
          values:
          - ap-south-1a                        # ← Must match EBS volume's AZ
---
# --- PersistentVolumeClaim ---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  resources:
    requests:
      storage: 10Gi
  volumeName: static-ebs-pv                    # ← Bind to our specific PV
---
# --- Pod ---
apiVersion: v1
kind: Pod
metadata:
  name: static-ebs-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c"]
    args:
    - |
      echo "=== Previous data ==="
      cat /data/log.txt 2>/dev/null || echo "(no previous data)"
      echo ""
      echo "Written by $(hostname) at $(date)" >> /data/log.txt
      echo "=== Current data ==="
      cat /data/log.txt
      sleep 3600
    volumeMounts:
    - name: ebs-vol
      mountPath: /data
  volumes:
  - name: ebs-vol
    persistentVolumeClaim:
      claimName: static-ebs-pvc
```

### Step 3: Apply and Verify

```bash
kubectl apply -f static-ebs-demo.yaml
# persistentvolume/static-ebs-pv created
# persistentvolumeclaim/static-ebs-pvc created
# pod/static-ebs-pod created

# Check PV and PVC are bound
kubectl get pv,pvc
# NAME                              CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   AGE
# persistentvolume/static-ebs-pv    10Gi       RWO            Retain           Bound    default/static-ebs-pvc                   10s
#
# NAME                                   STATUS   VOLUME          CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# persistentvolumeclaim/static-ebs-pvc   Bound    static-ebs-pv   10Gi       RWO                           10s

# Check pod is running
kubectl get pod static-ebs-pod -o wide
# NAME              READY   STATUS    RESTARTS   AGE   IP              NODE
# static-ebs-pod    1/1     Running   0          30s   192.168.1.50    ip-192-168-1-100...
# ^ Pod scheduled on a node in ap-south-1a (where the EBS volume is!)

# Check logs
kubectl logs static-ebs-pod
# === Previous data ===
# (no previous data)
#
# === Current data ===
# Written by static-ebs-pod at Fri Feb 28 10:00:00 UTC 2026

# Verify EBS is attached in AWS
aws ec2 describe-volumes --volume-ids vol-0abc123def456789 \
  --query "Volumes[0].Attachments[0].{State:State,InstanceId:InstanceId}" --output table
# -----------------------------------------
# |          Attachments                   |
# +----------------+-----------------------+
# |  InstanceId     |  i-0abcdef123456789  |
# |  State          |  attached            |
# +----------------+-----------------------+
```

### Step 4: Delete Pod, Recreate - Data Survives!

```bash
# Delete the pod
kubectl delete pod static-ebs-pod
# pod "static-ebs-pod" deleted

# Recreate
kubectl apply -f static-ebs-demo.yaml
# persistentvolume/static-ebs-pv unchanged
# persistentvolumeclaim/static-ebs-pvc unchanged
# pod/static-ebs-pod created

# Wait for pod to start
kubectl get pod static-ebs-pod -w

# Check logs - old data is still there!
kubectl logs static-ebs-pod
# === Previous data ===
# Written by static-ebs-pod at Fri Feb 28 10:00:00 UTC 2026    ← SURVIVED!
#
# === Current data ===
# Written by static-ebs-pod at Fri Feb 28 10:00:00 UTC 2026
# Written by static-ebs-pod at Fri Feb 28 10:05:00 UTC 2026    ← NEW ENTRY
```

### Clean Up

```bash
kubectl delete pod static-ebs-pod
kubectl delete pvc static-ebs-pvc
kubectl delete pv static-ebs-pv

# With Retain policy, EBS is NOT auto-deleted. Delete manually:
aws ec2 delete-volume --volume-id vol-0abc123def456789 --region ap-south-1
```

---

## Demo 2 - EBS Dynamic Provisioning with StorageClass

**Goal:** Let Kubernetes automatically create EBS volumes. No manual AWS work needed!

```
You create:                    K8s auto-creates:
===========                    =================
StorageClass (once)     →      (reusable template)
PVC                     →      EBS volume + PV (automatic!)
Pod                     →      Attaches EBS to node
```

### Step 1: Create StorageClass

```yaml
# ebs-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

```bash
kubectl apply -f ebs-storageclass.yaml
# storageclass.storage.k8s.io/ebs-gp3 created

kubectl get sc ebs-gp3
# NAME      PROVISIONER       RECLAIMPOLICY   VOLUMEBINDINGMODE       ALLOWVOLUMEEXPANSION   AGE
# ebs-gp3   ebs.csi.aws.com   Delete          WaitForFirstConsumer    true                   5s
```

### Step 2: Create PVC

```yaml
# dynamic-ebs-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 5Gi
```

```bash
kubectl apply -f dynamic-ebs-pvc.yaml
# persistentvolumeclaim/dynamic-ebs-pvc created

# PVC is Pending - waiting for a pod to need it!
kubectl get pvc dynamic-ebs-pvc
# NAME              STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# dynamic-ebs-pvc   Pending                                      ebs-gp3        5s
# ^ Pending because WaitForFirstConsumer - EBS not created yet
```

### Step 3: Create Pod - Triggers EBS Creation

```yaml
# dynamic-ebs-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: dynamic-ebs-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c"]
    args:
    - |
      echo "Dynamic EBS provisioning works!" > /data/test.txt
      echo "Pod: $(hostname), Date: $(date)" >> /data/test.txt
      cat /data/test.txt
      sleep 3600
    volumeMounts:
    - name: ebs-vol
      mountPath: /data
  volumes:
  - name: ebs-vol
    persistentVolumeClaim:
      claimName: dynamic-ebs-pvc
```

```bash
kubectl apply -f dynamic-ebs-pod.yaml
# pod/dynamic-ebs-pod created

# Watch the magic happen:
kubectl get pvc dynamic-ebs-pvc -w
# NAME              STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# dynamic-ebs-pvc   Pending                                                                        ebs-gp3        30s
# dynamic-ebs-pvc   Bound     pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   5Gi        RWO            ebs-gp3        45s
# ^ Status changed to Bound! EBS was auto-created!

# Check the auto-created PV
kubectl get pv
# NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   AGE
# pvc-a1b2c3d4-e5f6-7890-abcd-ef1234567890   5Gi        RWO            Delete           Bound    default/dynamic-ebs-pvc   ebs-gp3        15s

# Check pod logs
kubectl logs dynamic-ebs-pod
# Dynamic EBS provisioning works!
# Pod: dynamic-ebs-pod, Date: Fri Feb 28 10:30:00 UTC 2026

# Verify in AWS - a new 5GB gp3 volume was created!
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=dynamic-ebs-pvc" \
  --query "Volumes[0].{ID:VolumeId,Size:Size,Type:VolumeType,AZ:AvailabilityZone,Encrypted:Encrypted}" \
  --output table
# ---------------------------------------------------------------
# |                      Describe Volumes                        |
# +------+-------------+-----------+------+----------------------+
# | AZ   | Encrypted   | ID        | Size | Type                 |
# +------+-------------+-----------+------+----------------------+
# | ap-south-1a | True | vol-xxx  | 5    | gp3                  |
# +------+-------------+-----------+------+----------------------+
```

### Clean Up

```bash
kubectl delete pod dynamic-ebs-pod
kubectl delete pvc dynamic-ebs-pvc
# ^ This also deletes the EBS volume (reclaimPolicy: Delete)

# Verify EBS is gone
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=dynamic-ebs-pvc" \
  --query "Volumes[].VolumeId" --output text
# (empty - volume deleted!)

kubectl delete sc ebs-gp3
```

---

## Demo 3 - MySQL on EBS with Data Persistence

**Goal:** Run MySQL on EKS with EBS storage. Prove data survives pod deletion and rescheduling.

```
┌──── Pod: mysql ──────────┐
│                           │
│  ┌── mysql container ──┐ │
│  │  MySQL 8.0           │ │
│  │  /var/lib/mysql ─────┼─┼──► PVC (mysql-ebs-pvc)
│  │                      │ │        │
│  └──────────────────────┘ │        ▼
│                           │    StorageClass (ebs-gp3)
└───────────────────────────┘        │
                                     ▼
                              EBS Volume (gp3, 20Gi)
                              Auto-created by CSI driver
                              Data survives pod restarts!
```

### Step 1: Create StorageClass, PVC, Secret, and Deployment

```yaml
# mysql-ebs-full.yaml

# --- StorageClass ---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-mysql
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Retain                          # ← Retain for databases! Don't lose data
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# --- PVC ---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3-mysql
  resources:
    requests:
      storage: 20Gi
---
# --- Secret ---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  password: cm9vdHBhc3MxMjM=                  # base64 of "rootpass123"
---
# --- Deployment ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1                                  # ← EBS is RWO, only 1 replica!
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
        - name: MYSQL_DATABASE
          value: "testdb"
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
          claimName: mysql-ebs-pvc
---
# --- Service (to connect to MySQL) ---
apiVersion: v1
kind: Service
metadata:
  name: mysql-svc
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    targetPort: 3306
  type: ClusterIP
```

### Step 2: Apply and Wait for MySQL to Start

```bash
kubectl apply -f mysql-ebs-full.yaml
# storageclass.storage.k8s.io/ebs-gp3-mysql created
# persistentvolumeclaim/mysql-ebs-pvc created
# secret/mysql-secret created
# deployment.apps/mysql created
# service/mysql-svc created

# Watch pod start (takes ~60 seconds for EBS attach + MySQL init)
kubectl get pods -l app=mysql -w
# NAME                     READY   STATUS              RESTARTS   AGE
# mysql-7b8f9d6c5f-abc12   0/1     ContainerCreating   0          10s
# mysql-7b8f9d6c5f-abc12   1/1     Running             0          55s

# Verify PVC is bound
kubectl get pvc mysql-ebs-pvc
# NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS     AGE
# mysql-ebs-pvc   Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   20Gi       RWO            ebs-gp3-mysql    1m

# Check which node and AZ the pod is on
kubectl get pod -l app=mysql -o wide
# NODE: ip-192-168-1-100... (ap-south-1a)
```

### Step 3: Add Data to MySQL

```bash
# Connect to MySQL
kubectl exec -it $(kubectl get pod -l app=mysql -o name) -- \
  mysql -u root -prootpass123

# Inside MySQL:
mysql> USE testdb;
mysql> CREATE TABLE students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50),
    course VARCHAR(50),
    enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
mysql> INSERT INTO students (name, course) VALUES
    ('Alice', 'Kubernetes'),
    ('Bob', 'Docker'),
    ('Charlie', 'AWS'),
    ('Diana', 'Terraform');
mysql> SELECT * FROM students;
# +----+---------+------------+---------------------+
# | id | name    | course     | enrolled_at         |
# +----+---------+------------+---------------------+
# |  1 | Alice   | Kubernetes | 2026-02-28 10:30:00 |
# |  2 | Bob     | Docker     | 2026-02-28 10:30:00 |
# |  3 | Charlie | AWS        | 2026-02-28 10:30:00 |
# |  4 | Diana   | Terraform  | 2026-02-28 10:30:00 |
# +----+---------+------------+---------------------+
mysql> EXIT;
```

### Step 4: Delete Pod - Deployment Recreates It

```bash
# Delete the pod (NOT the deployment)
kubectl delete pod -l app=mysql
# pod "mysql-7b8f9d6c5f-abc12" deleted

# Deployment creates a new pod
kubectl get pods -l app=mysql -w
# NAME                     READY   STATUS              RESTARTS   AGE
# mysql-7b8f9d6c5f-xyz99   0/1     ContainerCreating   0          5s
# mysql-7b8f9d6c5f-xyz99   1/1     Running             0          45s
# ^ New pod name! But same PVC, same EBS volume

# Check data - STILL THERE!
kubectl exec -it $(kubectl get pod -l app=mysql -o name) -- \
  mysql -u root -prootpass123 -e "SELECT * FROM testdb.students;"
# +----+---------+------------+---------------------+
# | id | name    | course     | enrolled_at         |
# +----+---------+------------+---------------------+
# |  1 | Alice   | Kubernetes | 2026-02-28 10:30:00 |
# |  2 | Bob     | Docker     | 2026-02-28 10:30:00 |
# |  3 | Charlie | AWS        | 2026-02-28 10:30:00 |
# |  4 | Diana   | Terraform  | 2026-02-28 10:30:00 |
# +----+---------+------------+---------------------+
# DATA SURVIVED POD DELETION!
```

### Step 5: EBS Volume Expansion (Need More Space)

```bash
# Check current size
kubectl get pvc mysql-ebs-pvc
# CAPACITY: 20Gi

# Expand to 50Gi
kubectl patch pvc mysql-ebs-pvc \
  -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
# persistentvolumeclaim/mysql-ebs-pvc patched

# Watch the expansion (takes 1-2 minutes)
kubectl get pvc mysql-ebs-pvc -w
# CAPACITY: 20Gi  →  50Gi

# Verify in AWS
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=mysql-ebs-pvc" \
  --query "Volumes[0].Size" --output text
# 50
```

### Clean Up

```bash
kubectl delete deployment mysql
kubectl delete svc mysql-svc
kubectl delete secret mysql-secret
kubectl delete pvc mysql-ebs-pvc

# With Retain policy, PV still exists:
kubectl get pv
# STATUS: Released

# Delete PV and EBS manually:
kubectl delete pv <pv-name>
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=mysql-ebs-pvc" \
  --query "Volumes[0].VolumeId" --output text
# vol-xxxxxxx
aws ec2 delete-volume --volume-id vol-xxxxxxx

kubectl delete sc ebs-gp3-mysql
```

---

## Demo 4 - EFS Shared Storage (Multiple Pods)

**Goal:** Multiple pods on different nodes sharing the same files using EFS (ReadWriteMany).

```
  ┌──── Node 1 ────────────┐     ┌──── Node 2 ────────────┐
  │                         │     │                         │
  │  writer-1 (writes)      │     │  writer-2 (writes)      │
  │    ↓                    │     │    ↓                    │
  └────┼────────────────────┘     └────┼────────────────────┘
       │                               │
       └───────────┬───────────────────┘
                   ↓
            ┌─────────────┐
            │  EFS Volume  │    ← All pods read/write
            │  (shared)    │       the SAME files!
            └─────────────┘
                   ↑
       ┌───────────┘
       │
  ┌────┼────────────────────┐
  │  reader (reads)          │
  │    ↑                    │
  │  Node 1 or Node 2       │
  └─────────────────────────┘
```

### Pre-requisite: Create EFS Filesystem

```bash
# Get your VPC ID
VPC_ID=$(aws eks describe-cluster --name my-cluster \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Get subnet IDs
SUBNET_IDS=$(aws eks describe-cluster --name my-cluster \
  --query "cluster.resourcesVpcConfig.subnetIds" --output text)

# Create security group for EFS
SG_ID=$(aws ec2 create-security-group \
  --group-name efs-sg \
  --description "EFS for EKS" \
  --vpc-id $VPC_ID \
  --query "GroupId" --output text)

# Allow NFS traffic from VPC
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID \
  --query "Vpcs[0].CidrBlock" --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr $VPC_CIDR

# Create EFS filesystem
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value=eks-shared-efs \
  --query "FileSystemId" --output text)

echo "EFS ID: $EFS_ID"
# EFS ID: fs-0123456789abcdef0    ← NOTE THIS!

# Create mount targets in each subnet
for SUBNET in $SUBNET_IDS; do
  aws efs create-mount-target \
    --file-system-id $EFS_ID \
    --subnet-id $SUBNET \
    --security-groups $SG_ID 2>/dev/null
done

# Wait for mount targets to be available (~1-2 minutes)
aws efs describe-mount-targets --file-system-id $EFS_ID \
  --query "MountTargets[].LifeCycleState" --output text
# available available
```

### Step 1: Create StorageClass and PVC for EFS

```yaml
# efs-demo.yaml

# --- StorageClass ---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-0123456789abcdef0           # ← Replace with YOUR EFS ID!
  directoryPerms: "700"
  basePath: "/demo"
reclaimPolicy: Delete
---
# --- PVC (ReadWriteMany!) ---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-efs-pvc
spec:
  accessModes:
    - ReadWriteMany                            # ← Multiple pods can read AND write!
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi                             # ← EFS is elastic, this is just a label
```

```bash
kubectl apply -f efs-demo.yaml
# storageclass.storage.k8s.io/efs-sc created
# persistentvolumeclaim/shared-efs-pvc created

kubectl get pvc shared-efs-pvc
# NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# shared-efs-pvc    Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWX            efs-sc         10s
# ^ RWX = ReadWriteMany!
```

### Step 2: Deploy Writers and Reader

```yaml
# efs-pods.yaml

# --- Writer Deployment (2 replicas on different nodes) ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: efs-writer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: efs-writer
  template:
    metadata:
      labels:
        app: efs-writer
    spec:
      containers:
      - name: writer
        image: busybox
        command: ["sh", "-c"]
        args:
        - |
          while true; do
            echo "[$(hostname)] wrote at $(date)" >> /shared/log.txt
            echo "Writer $(hostname): wrote entry"
            sleep 5
          done
        volumeMounts:
        - name: shared
          mountPath: /shared
      volumes:
      - name: shared
        persistentVolumeClaim:
          claimName: shared-efs-pvc            # ← Same PVC for all!
---
# --- Reader Deployment ---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: efs-reader
spec:
  replicas: 1
  selector:
    matchLabels:
      app: efs-reader
  template:
    metadata:
      labels:
        app: efs-reader
    spec:
      containers:
      - name: reader
        image: busybox
        command: ["sh", "-c"]
        args:
        - |
          while true; do
            echo "=== Last 5 entries from shared log ==="
            tail -5 /shared/log.txt 2>/dev/null || echo "(no data yet)"
            echo ""
            sleep 5
          done
        volumeMounts:
        - name: shared
          mountPath: /shared
      volumes:
      - name: shared
        persistentVolumeClaim:
          claimName: shared-efs-pvc            # ← Same PVC!
```

```bash
kubectl apply -f efs-pods.yaml
# deployment.apps/efs-writer created
# deployment.apps/efs-reader created

# Check pods are on DIFFERENT nodes
kubectl get pods -o wide -l 'app in (efs-writer,efs-reader)'
# NAME                          READY   STATUS    NODE
# efs-writer-xxxxxx-abc12       1/1     Running   ip-192-168-1-100... (Node 1)
# efs-writer-xxxxxx-def34       1/1     Running   ip-192-168-2-200... (Node 2)
# efs-reader-xxxxxx-ghi56       1/1     Running   ip-192-168-1-100... (Node 1)
# ^ Writers on DIFFERENT nodes, all sharing the SAME EFS!

# Check writer logs
kubectl logs -l app=efs-writer --tail=3
# Writer efs-writer-xxxxxx-abc12: wrote entry
# Writer efs-writer-xxxxxx-def34: wrote entry
# Writer efs-writer-xxxxxx-abc12: wrote entry

# Check reader logs - sees writes from BOTH writers!
kubectl logs -l app=efs-reader --tail=10
# === Last 5 entries from shared log ===
# [efs-writer-xxxxxx-abc12] wrote at Fri Feb 28 11:00:10 UTC 2026
# [efs-writer-xxxxxx-def34] wrote at Fri Feb 28 11:00:12 UTC 2026
# [efs-writer-xxxxxx-abc12] wrote at Fri Feb 28 11:00:15 UTC 2026
# [efs-writer-xxxxxx-def34] wrote at Fri Feb 28 11:00:17 UTC 2026
# [efs-writer-xxxxxx-abc12] wrote at Fri Feb 28 11:00:20 UTC 2026
```

Both writer pods (on different nodes) write to the same EFS, and the reader pod sees all entries!

### Clean Up

```bash
kubectl delete deployment efs-writer efs-reader
kubectl delete pvc shared-efs-pvc
kubectl delete sc efs-sc

# Optionally delete EFS filesystem if no longer needed:
# aws efs delete-file-system --file-system-id fs-0123456789abcdef0
```

---

## Demo 5 - StatefulSet with Per-Replica EBS

**Goal:** Each StatefulSet replica gets its own EBS volume using `volumeClaimTemplates`. This is how databases run in production.

```
StatefulSet creates:

  mysql-0 (Pod)          mysql-1 (Pod)          mysql-2 (Pod)
     ↓                      ↓                      ↓
  mysql-data-mysql-0     mysql-data-mysql-1     mysql-data-mysql-2
  (PVC, auto-created)   (PVC, auto-created)   (PVC, auto-created)
     ↓                      ↓                      ↓
  EBS vol-aaa (20Gi)     EBS vol-bbb (20Gi)     EBS vol-ccc (20Gi)
  (auto-created)         (auto-created)         (auto-created)

  3 pods × 1 EBS each = 3 separate EBS volumes
  Each pod has its OWN independent storage!
```

### Step 1: Create StorageClass and Headless Service

```yaml
# statefulset-demo.yaml

# --- StorageClass ---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-sts
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
  encrypted: "true"
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# --- Headless Service (required for StatefulSet) ---
apiVersion: v1
kind: Service
metadata:
  name: web-headless
spec:
  clusterIP: None                              # ← Headless! No load balancing
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
```

### Step 2: Create StatefulSet with volumeClaimTemplates

```yaml
# statefulset-pods.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  replicas: 3
  serviceName: web-headless                    # ← Must match headless service name
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: app
        image: busybox
        command: ["sh", "-c"]
        args:
        - |
          # Write pod identity to its own volume
          echo "I am $(hostname)" > /data/identity.txt
          echo "Created at $(date)" >> /data/identity.txt
          echo "=== My storage contents ==="
          cat /data/identity.txt
          # Keep pod running
          while true; do
            echo "$(hostname) is alive at $(date)" >> /data/log.txt
            sleep 10
          done
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:                        # ← Each replica gets its OWN PVC!
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: ebs-gp3-sts
      resources:
        requests:
          storage: 5Gi
```

### Step 3: Apply and Observe

```bash
kubectl apply -f statefulset-demo.yaml
kubectl apply -f statefulset-pods.yaml

# Watch pods come up ONE BY ONE (ordered startup!)
kubectl get pods -l app=web -w
# NAME    READY   STATUS              RESTARTS   AGE
# web-0   0/1     ContainerCreating   0          5s
# web-0   1/1     Running             0          40s
# web-1   0/1     ContainerCreating   0          45s     ← Starts AFTER web-0 is ready
# web-1   1/1     Running             0          80s
# web-2   0/1     ContainerCreating   0          85s     ← Starts AFTER web-1 is ready
# web-2   1/1     Running             0          120s

# Check PVCs - 3 auto-created! One per replica
kubectl get pvc
# NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# data-web-0     Bound    pvc-aaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa       5Gi        RWO            ebs-gp3-sts    2m
# data-web-1     Bound    pvc-bbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb       5Gi        RWO            ebs-gp3-sts    90s
# data-web-2     Bound    pvc-cccc-cccc-cccc-cccc-cccccccccccc       5Gi        RWO            ebs-gp3-sts    45s
# ^ Each pod got its OWN PVC → its OWN EBS volume!

# Verify each pod has its own identity
kubectl logs web-0
# === My storage contents ===
# I am web-0
# Created at Fri Feb 28 12:00:00 UTC 2026

kubectl logs web-1
# === My storage contents ===
# I am web-1
# Created at Fri Feb 28 12:00:40 UTC 2026

kubectl logs web-2
# === My storage contents ===
# I am web-2
# Created at Fri Feb 28 12:01:20 UTC 2026

# Each pod wrote to its OWN volume - they don't share!
```

### Step 4: Delete a Pod - StatefulSet Recreates with SAME Volume

```bash
# Delete web-1
kubectl delete pod web-1
# pod "web-1" deleted

# StatefulSet recreates web-1 (same name, same PVC!)
kubectl get pods -l app=web -w
# web-1   0/1     ContainerCreating   0          5s
# web-1   1/1     Running             0          35s

# Check web-1's data - OLD DATA IS STILL THERE!
kubectl exec web-1 -- cat /data/identity.txt
# I am web-1
# Created at Fri Feb 28 12:00:40 UTC 2026    ← Original creation time!

kubectl exec web-1 -- cat /data/log.txt
# web-1 is alive at Fri Feb 28 12:00:50 UTC 2026    ← Old entries
# web-1 is alive at Fri Feb 28 12:01:00 UTC 2026
# ...
# web-1 is alive at Fri Feb 28 12:05:00 UTC 2026    ← New entries after recreate

# The PVC data-web-1 was NOT deleted, so web-1 got its old data back!
kubectl get pvc data-web-1
# STATUS: Bound    (same PV as before)
```

### Step 5: Scale Down and Back Up

```bash
# Scale down to 1
kubectl scale statefulset web --replicas=1
# statefulset.apps/web scaled

# web-2 deleted first, then web-1 (reverse order!)
kubectl get pods -l app=web
# NAME    READY   STATUS    AGE
# web-0   1/1     Running   10m

# But PVCs are NOT deleted! (data preserved)
kubectl get pvc
# NAME           STATUS   VOLUME     CAPACITY   AGE
# data-web-0     Bound    pvc-aaa    5Gi        10m
# data-web-1     Bound    pvc-bbb    5Gi        10m     ← Still exists!
# data-web-2     Bound    pvc-ccc    5Gi        10m     ← Still exists!

# Scale back up to 3
kubectl scale statefulset web --replicas=3

# web-1 and web-2 come back with SAME PVCs, SAME DATA!
kubectl exec web-1 -- cat /data/identity.txt
# I am web-1
# Created at Fri Feb 28 12:00:40 UTC 2026    ← Original data!

kubectl exec web-2 -- cat /data/identity.txt
# I am web-2
# Created at Fri Feb 28 12:01:20 UTC 2026    ← Original data!
```

### Clean Up

```bash
kubectl delete statefulset web
kubectl delete svc web-headless

# StatefulSet does NOT delete PVCs automatically (data safety!)
# You must delete them manually:
kubectl delete pvc data-web-0 data-web-1 data-web-2

# With Retain policy, PVs also need manual cleanup:
kubectl delete pv --all

kubectl delete sc ebs-gp3-sts
```

---

## Demo 6 - Multi-Replica Deployment with EBS (Failure Demo)

**Goal:** Show what happens when you try to use EBS with a Deployment that has multiple replicas. This is a common mistake!

```
WHAT STUDENTS EXPECT:          WHAT ACTUALLY HAPPENS:

  Pod-1 ──┐                     Pod-1 (Running)
  Pod-2 ──┤── same EBS          Pod-2 (STUCK - Multi-Attach error!)
  Pod-3 ──┘                     Pod-3 (STUCK - Multi-Attach error!)
```

### Step 1: Create the "Wrong" Setup

```yaml
# multi-replica-ebs-fail.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-fail
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-ebs-pvc
spec:
  accessModes:
    - ReadWriteOnce                            # ← EBS is RWO!
  storageClassName: ebs-gp3-fail
  resources:
    requests:
      storage: 5Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-replica-fail
spec:
  replicas: 3                                  # ← 3 replicas...
  selector:
    matchLabels:
      app: fail-demo
  template:
    metadata:
      labels:
        app: fail-demo
    spec:
      containers:
      - name: app
        image: busybox
        command: ["sh", "-c", "echo 'Running on $(hostname)' && sleep 3600"]
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: shared-ebs-pvc            # ← All 3 try to use SAME EBS!
```

### Step 2: Apply and Watch It Fail

```bash
kubectl apply -f multi-replica-ebs-fail.yaml

# Watch pods
kubectl get pods -l app=fail-demo -w
# NAME                                  READY   STATUS              RESTARTS   AGE
# multi-replica-fail-xxxx-abc12         1/1     Running             0          30s      ← This one works!
# multi-replica-fail-xxxx-def34         0/1     ContainerCreating   0          30s      ← STUCK
# multi-replica-fail-xxxx-ghi56         0/1     ContainerCreating   0          30s      ← STUCK

# Check why they're stuck
kubectl describe pod multi-replica-fail-xxxx-def34 | grep -A 5 "Events"
# Events:
#   Type     Reason              Age   Message
#   ----     ------              ----  -------
#   Warning  FailedAttachVolume  30s   Multi-Attach error for volume "pvc-xxx"
#                                       Volume is already exclusively attached to one node
#                                       and can't be attached to another

# Only 1 out of 3 pods is running!
kubectl get pods -l app=fail-demo
# NAME                                  READY   STATUS              AGE
# multi-replica-fail-xxxx-abc12         1/1     Running             2m
# multi-replica-fail-xxxx-def34         0/1     ContainerCreating   2m    ← Stuck forever
# multi-replica-fail-xxxx-ghi56         0/1     ContainerCreating   2m    ← Stuck forever
```

```
LESSON LEARNED:
  EBS (ReadWriteOnce) + Deployment with replicas > 1 = BROKEN!

  Solutions:
  1. Use StatefulSet with volumeClaimTemplates (each replica gets own EBS)
     → For databases (MySQL, Mongo, Kafka)
  2. Use EFS (ReadWriteMany) instead of EBS
     → For shared files (WordPress uploads, configs, ML data)
  3. Keep replicas: 1 if using EBS with Deployment
     → For single-instance databases
```

### Clean Up

```bash
kubectl delete deployment multi-replica-fail
kubectl delete pvc shared-ebs-pvc
kubectl delete sc ebs-gp3-fail
```

---

## Summary of All EKS Demos

| Demo | What It Shows | Storage | Key Lesson |
|------|--------------|---------|------------|
| 1 - Static EBS | Manual EBS → PV → PVC → Pod | EBS (static) | Understand the full flow |
| 2 - Dynamic EBS | StorageClass auto-creates EBS | EBS (dynamic) | Production recommended |
| 3 - MySQL on EBS | Database with persistence | EBS (dynamic) | Data survives pod restarts |
| 4 - EFS Shared | Multiple pods share files | EFS (RWX) | Cross-node file sharing |
| 5 - StatefulSet | Per-replica volumes | EBS (per pod) | How databases use storage |
| 6 - Failure Demo | Multi-replica + EBS = broken | EBS (fails) | Don't use EBS with replicas > 1 |

---

## Key Takeaways

1. **Static provisioning** = you create EBS manually, useful for migration and learning
2. **Dynamic provisioning** = StorageClass + PVC, K8s creates EBS automatically (use this!)
3. **WaitForFirstConsumer** ensures EBS is created in the same AZ as your pod
4. **EBS is RWO** - only 1 node can mount it. Multiple replicas = Multi-Attach error
5. **EFS is RWX** - multiple pods on multiple nodes can share it
6. **StatefulSet + volumeClaimTemplates** = each replica gets its own EBS volume
7. **Use Retain reclaim policy for databases** - prevents accidental data loss
8. **EBS volume expansion** works if StorageClass has allowVolumeExpansion: true
9. **PVCs are NOT deleted** when you scale down a StatefulSet - data is preserved
10. **Always verify EBS in AWS Console** - check EC2 → Volumes to see real volumes

---

## Practice / Homework

1. Create an EBS volume manually in AWS and use it in a pod (static provisioning)
2. Create a StorageClass and PVC, deploy a pod, and verify EBS was auto-created in AWS
3. Run MySQL on EBS, add data, delete the pod, recreate, and verify data survives
4. Expand an EBS PVC from 5Gi to 10Gi and verify the change in AWS
5. Deploy 2 writers + 1 reader using EFS and verify shared file access across nodes
6. Create a StatefulSet with 3 replicas and verify each gets its own PVC/EBS
7. Try the failure demo: 3 replicas + 1 EBS PVC, observe the Multi-Attach error
8. Scale a StatefulSet down to 1, then back to 3, and verify data is preserved

---

**Related:** [Volumes Theory](../day12-volumes/notes.md) | [AWS Volumes Theory (EBS & EFS)](../day12-volumes/aws-volumes/notes.md) | [Local Demos (Minikube)](notes.md)
**Previous:** [← Day 12 - Volumes (Theory)](../day12-volumes/notes.md)
**Next:** [Day 14 - Ingress →](../day14-ingress/notes.md)
