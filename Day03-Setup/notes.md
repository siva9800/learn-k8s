# Day 03 - Setting Up Kubernetes (Minikube + kubectl)

## Why Can't We Just Install Kubernetes Directly?

Kubernetes is designed to run on **multiple servers** (a cluster). But for learning, we don't need multiple servers. We use tools that simulate a K8s cluster on your laptop.

| Tool | What It Does | Best For |
|------|-------------|----------|
| **Minikube** | Creates a single-node K8s cluster in a VM/container | Learning, local development |
| **kind** | Runs K8s inside Docker containers | CI/CD testing |
| **kubeadm** | Sets up a real multi-node cluster | Production-like setup |
| **Managed K8s** | AWS EKS, Azure AKS, Google GKE | Real production |

We'll use **Minikube** - it's the easiest for beginners.

---

## Step 1: Install kubectl (The K8s CLI Tool)

`kubectl` is the command-line tool you use to interact with Kubernetes. You'll use it every single day.

### On Windows

```bash
# Using chocolatey
choco install kubernetes-cli

# Or download directly
curl -LO "https://dl.k8s.io/release/v1.31.0/bin/windows/amd64/kubectl.exe"
# Move kubectl.exe to a folder in your PATH
```

### On macOS

```bash
# Using Homebrew
brew install kubectl
```

### On Linux

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

### Verify Installation

```bash
kubectl version --client
```

---

## Step 2: Install Minikube

### On Windows

```bash
# Using chocolatey
choco install minikube

# Or download from: https://minikube.sigs.k8s.io/docs/start/
```

### On macOS

```bash
brew install minikube
```

### On Linux

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

### Prerequisites for Minikube

Minikube needs a **driver** to create the VM/container. Options:
- **Docker** (recommended) - Install Docker Desktop
- **VirtualBox** - Install VirtualBox
- **Hyper-V** (Windows) - Enable in Windows Features

---

## Step 3: Start Your First Cluster!

```bash
# Start minikube with Docker driver (recommended)
minikube start --driver=docker

# Or with specific resources
minikube start --driver=docker --cpus=2 --memory=4096
```

**Expected Output:**
```
😄  minikube v1.32.0 on Windows 10
✨  Using the docker driver
📌  Using Docker Desktop driver
🔥  Creating docker container (CPUs=2, Memory=4096MB)
🐳  Preparing Kubernetes v1.28.3 on Docker
🔎  Verifying Kubernetes components...
🌟  Enabled addons: storage-provisioner, default-storageclass
🏄  Done! kubectl is now configured to use "minikube" cluster
```

---

## Step 4: Verify Everything Works

Run these commands one by one:

```bash
# Check cluster status
minikube status

# Check kubectl can talk to cluster
kubectl cluster-info

# See the single node
kubectl get nodes

# See all running system pods
kubectl get pods -n kube-system
```

### Expected Output for `kubectl get nodes`:

```
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   5m    v1.28.3
```

### Expected Output for `kubectl get pods -n kube-system`:

```
NAME                               READY   STATUS    RESTARTS   AGE
coredns-5dd5756b68-xxxxx           1/1     Running   0          5m
etcd-minikube                      1/1     Running   0          5m
kube-apiserver-minikube            1/1     Running   0          5m
kube-controller-manager-minikube   1/1     Running   0          5m
kube-proxy-xxxxx                   1/1     Running   0          5m
kube-scheduler-minikube            1/1     Running   0          5m
storage-provisioner                1/1     Running   0          5m
```

**Notice:** You can see all the components from Day 02 running as pods! (API Server, etcd, Controller Manager, Scheduler, Proxy)

---

## Step 5: Useful Minikube Commands

```bash
# Stop the cluster (saves resources)
minikube stop

# Start it again
minikube start

# Delete the cluster completely
minikube delete

# Open Kubernetes Dashboard (web UI)
minikube dashboard

# Check minikube IP
minikube ip

# SSH into the minikube node
minikube ssh
```

---

## Understanding kubectl Command Structure

```
kubectl  <action>  <resource>  <options>
   │        │         │           │
   │        │         │           └── flags like -n, -o, --all
   │        │         └── pod, deployment, service, node, etc.
   │        └── get, describe, create, apply, delete, logs, exec
   └── the K8s CLI tool
```

### Examples:

```bash
kubectl get pods                    # List all pods
kubectl get pods -n kube-system     # List pods in kube-system namespace
kubectl get pods -o wide            # List pods with more details
kubectl get all                     # List all resources
kubectl describe pod <name>         # Detailed info about a pod
kubectl logs <pod-name>             # View pod logs
kubectl delete pod <pod-name>       # Delete a pod
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| "minikube not found" | Add minikube to your PATH |
| "Docker not running" | Start Docker Desktop first |
| "Insufficient memory" | Use `--memory=2048` flag |
| "kubectl connection refused" | Run `minikube start` first |
| Cluster is slow | Allocate more CPUs: `--cpus=4` |

---

## Practice / Homework

1. Install Minikube and kubectl on your machine
2. Start a cluster with `minikube start`
3. Run these commands and observe the output:
   ```bash
   kubectl get nodes
   kubectl get pods -n kube-system
   kubectl cluster-info
   minikube dashboard
   ```
4. Stop the cluster with `minikube stop`
5. Start it again and verify everything works

---

**Previous:** [← Day 02 - Architecture](../Day02-Architecture/notes.md)
**Next:** [Day 04 - Pods →](../Day04-Pods/notes.md)
