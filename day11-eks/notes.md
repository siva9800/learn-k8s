# Day 11 - Amazon EKS (Elastic Kubernetes Service)

## Why EKS? Why Not Just Minikube?

So far we've been using **Minikube** - a single-node K8s cluster on your laptop. That's great for learning, but in production you need:

| Minikube (Local) | EKS (Production) |
|-------------------|-------------------|
| Single node | Multiple nodes across availability zones |
| Your laptop's resources | AWS cloud resources (auto-scaling) |
| No high availability | High availability built-in |
| You manage everything | AWS manages the control plane |
| Free | Pay-as-you-go |
| For learning/testing | For real production workloads |

---

## What Is EKS?

**EKS** = Amazon Elastic Kubernetes Service

AWS runs and manages the **control plane** (master node) for you. You only manage the **worker nodes**.

```
┌──── AWS Manages This ────┐
│                           │
│  ┌─────────────────────┐  │
│  │   Control Plane     │  │
│  │   (Master Node)     │  │
│  │                     │  │
│  │  API Server         │  │
│  │  etcd               │  │
│  │  Scheduler          │  │
│  │  Controller Manager │  │
│  └─────────────────────┘  │
│                           │
│  - Multi-AZ (high avail) │
│  - Auto patching          │
│  - Auto backup            │
└───────────────────────────┘
            │
            │ connects
            │
┌──── You Manage This ─────┐
│                           │
│  ┌────────┐ ┌────────┐   │
│  │Worker 1│ │Worker 2│   │
│  │(EC2)   │ │(EC2)   │   │
│  │        │ │        │   │
│  │ Pods   │ │ Pods   │   │
│  └────────┘ └────────┘   │
│                           │
│  Your applications run    │
│  here on EC2 instances    │
└───────────────────────────┘
```

---

## EKS vs Self-Managed K8s

| Feature | Self-Managed K8s | EKS |
|---------|-----------------|-----|
| Control plane setup | You do it (hard!) | AWS does it |
| etcd management | You back it up, patch it | AWS handles it |
| Control plane upgrades | Manual, risky | One-click |
| High availability | You configure it | Built-in (multi-AZ) |
| Cost | EC2 for master + worker | $0.10/hr for control plane + worker EC2 |
| Networking | You install CNI | AWS VPC CNI (pre-installed) |
| IAM integration | Manual | Native AWS IAM |
| Load balancer | Manual setup | Auto-provisions AWS ALB/NLB |

---

## Prerequisites

Before creating an EKS cluster, you need:

### 1. AWS CLI

```bash
# Install AWS CLI
# Windows
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-south-1 (or your preferred region)
# Default output format: json
```

### 2. kubectl (Already installed from Day 03)

```bash
kubectl version --client
```

### 3. eksctl (EKS CLI tool - makes everything easy!)

```bash
# Windows
choco install eksctl

# macOS
brew tap weaveworks/tap
brew install weaveworks/tap/eksctl

# Linux
curl --silent --location "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Verify
eksctl version
```

---

## Method 1: Create EKS Cluster with eksctl (Easiest)

### Create Cluster

```bash
# Simple cluster (takes 15-20 minutes)
eksctl create cluster \
  --name my-cluster \
  --region ap-south-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3
```

### What This Creates

```
AWS Resources Created:
├── VPC with public and private subnets
├── Internet Gateway
├── NAT Gateway
├── Security Groups
├── EKS Control Plane
├── IAM Roles (for cluster and nodes)
├── EC2 instances (worker nodes)
└── Auto Scaling Group
```

### Verify

```bash
# Check cluster
eksctl get cluster

# kubectl is automatically configured
kubectl get nodes
# NAME                                           STATUS   ROLES    AGE
# ip-192-168-1-100.ap-south-1.compute.internal   Ready    <none>   5m
# ip-192-168-2-200.ap-south-1.compute.internal   Ready    <none>   5m

# Check all namespaces
kubectl get pods -A
```

---

## Method 2: Create EKS Cluster with YAML (More Control)

```yaml
# cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: my-cluster
  region: ap-south-1
  version: "1.29"

managedNodeGroups:
  - name: workers
    instanceType: t3.medium
    minSize: 1
    maxSize: 3
    desiredCapacity: 2
    volumeSize: 20
    ssh:
      allow: true
    labels:
      role: worker
    tags:
      environment: dev
```

```bash
eksctl create cluster -f cluster.yaml
```

---

## Method 3: Create via AWS Console (UI)

```
1. Go to AWS Console → EKS → Create Cluster
2. Enter cluster name, K8s version, select IAM role
3. Configure networking (VPC, subnets, security groups)
4. Select add-ons (CoreDNS, kube-proxy, VPC CNI)
5. Review and create
6. Add Node Group after cluster is ready
7. Configure kubectl:
   aws eks update-kubeconfig --name my-cluster --region ap-south-1
```

---

## Connecting kubectl to EKS

```bash
# Update kubeconfig (tells kubectl to talk to your EKS cluster)
aws eks update-kubeconfig --name my-cluster --region ap-south-1

# Verify connection
kubectl cluster-info
# Kubernetes control plane is running at https://XXXXX.eks.amazonaws.com

kubectl get nodes
```

---

## Deploy an Application on EKS

Everything you learned on Minikube works exactly the same on EKS!

```bash
# Create a deployment
kubectl create deployment web --image=nginx:1.27 --replicas=3

# Expose with LoadBalancer (this creates an AWS ALB/NLB!)
kubectl expose deployment web --type=LoadBalancer --port=80

# Check the service
kubectl get svc web
# NAME   TYPE           CLUSTER-IP    EXTERNAL-IP                              PORT(S)
# web    LoadBalancer   10.100.0.50   abc123-456.ap-south-1.elb.amazonaws.com  80:31234/TCP

# Access your app via the AWS Load Balancer URL!
curl http://abc123-456.ap-south-1.elb.amazonaws.com
```

**Key difference from Minikube:** `LoadBalancer` type actually provisions a real AWS Load Balancer with a public URL!

---

## EKS Node Types

### Managed Node Groups (Recommended)

```
AWS manages EC2 instances for you
- Auto-patching
- Easy upgrades
- Auto-scaling
```

### Self-Managed Nodes

```
You manage your own EC2 instances
- Full control
- More work
```

### Fargate (Serverless)

```
No EC2 instances at all!
- AWS runs pods for you
- Pay per pod (no idle cost)
- No node management
- Some limitations (no DaemonSets, no hostPath)
```

```bash
# Create cluster with Fargate
eksctl create cluster \
  --name fargate-cluster \
  --region ap-south-1 \
  --fargate
```

---

## EKS + AWS Services Integration

| K8s Concept | AWS Integration |
|-------------|----------------|
| **Service (LoadBalancer)** | Creates AWS ALB/NLB automatically |
| **Ingress** | AWS ALB Ingress Controller |
| **Persistent Volumes** | AWS EBS (block) or EFS (file) |
| **Secrets** | AWS Secrets Manager |
| **IAM** | IAM Roles for Service Accounts (IRSA) |
| **Logging** | CloudWatch Container Insights |
| **Monitoring** | CloudWatch + Prometheus |
| **Container Registry** | Amazon ECR |

---

## Scaling on EKS

### Manual Scaling

```bash
# Scale node group
eksctl scale nodegroup \
  --cluster my-cluster \
  --name workers \
  --nodes 4

# Scale deployment
kubectl scale deployment web --replicas=10
```

### Cluster Autoscaler

Automatically adds/removes nodes based on pod demand:

```bash
# Install Cluster Autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

When pods are pending (no space on existing nodes) → Autoscaler adds a new node.
When nodes are underutilized → Autoscaler removes them.

---

## Important: Cost Management!

EKS costs money! Always clean up when done.

```
EKS Costs:
├── Control Plane: $0.10/hour (~$73/month)
├── Worker Nodes: EC2 pricing (t3.medium ~$30/month each)
├── NAT Gateway: ~$32/month
├── Load Balancers: ~$16/month each
└── Storage (EBS): ~$0.10/GB/month
```

### Delete Cluster When Done!

```bash
# Delete everything (cluster + node groups + VPC)
eksctl delete cluster --name my-cluster --region ap-south-1

# Verify no resources are left
aws eks list-clusters
```

---

## EKS vs Other Managed K8s

| Feature | EKS (AWS) | GKE (Google) | AKS (Azure) |
|---------|-----------|--------------|-------------|
| Control plane cost | $0.10/hr | Free (1 cluster) | Free |
| Ease of setup | Medium | Easy | Easy |
| Best integration | AWS services | GCP services | Azure services |
| CLI tool | eksctl | gcloud | az aks |
| Default CNI | AWS VPC CNI | Calico | Azure CNI |

---

## Useful Commands

```bash
# Cluster management
eksctl create cluster -f cluster.yaml
eksctl get cluster
eksctl delete cluster --name my-cluster

# Node groups
eksctl get nodegroup --cluster my-cluster
eksctl scale nodegroup --cluster my-cluster --name workers --nodes 3

# Connect kubectl
aws eks update-kubeconfig --name my-cluster --region ap-south-1

# Check connection
kubectl cluster-info
kubectl get nodes
```

---

## Key Takeaways

1. **EKS** = AWS-managed Kubernetes (control plane managed by AWS)
2. **eksctl** = easiest way to create/manage EKS clusters
3. **Everything you learned on Minikube works on EKS** (same kubectl, same YAML)
4. **LoadBalancer** type creates real AWS load balancers on EKS
5. **Managed Node Groups** = recommended (AWS handles patching/upgrades)
6. **Fargate** = serverless option (no nodes to manage)
7. **Always delete your cluster** when not in use to avoid charges!
8. Use **Cluster Autoscaler** for automatic scaling in production

---



**Previous:** [← Day 10 - ConfigMaps & Secrets](../day10-configmaps-secrets/notes.md)
**Next:** [Day 12 - Volumes & Persistent Storage →](../day12-volumes/notes.md)
