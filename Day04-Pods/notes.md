# Day 04 - Pods

## What Is a Pod?

A **Pod** is the smallest deployable unit in Kubernetes. It's a wrapper around one or more containers.

> **You don't deploy containers directly in K8s. You deploy Pods.**

```
┌─────────── Pod ───────────┐
│                            │
│  ┌──────────────────────┐  │
│  │     Container         │  │
│  │   (your app - nginx)  │  │
│  └──────────────────────┘  │
│                            │
│  - Shared IP address       │
│  - Shared storage          │
│  - Shared network          │
└────────────────────────────┘
```

### Why Not Just Use Containers?

| Without Pods (Docker) | With Pods (K8s) |
|----------------------|-----------------|
| Each container has its own IP | All containers in a pod share one IP |
| Networking between containers is manual | Containers in same pod talk via `localhost` |
| No health monitoring | K8s monitors and restarts unhealthy pods |
| No scheduling | K8s decides which server runs the pod |

---

## One Container Per Pod (The Standard Way)

In 90% of cases, one pod = one container. This is the recommended pattern.

```yaml
# One container per pod (recommended)
┌── Pod ──┐
│ ┌─────┐ │
│ │nginx│ │
│ └─────┘ │
└─────────┘
```

## Multi-Container Pod (Advanced - Sidecar Pattern)

Sometimes you need helper containers alongside your main app:

```yaml
# Multi-container pod (special cases)
┌────── Pod ──────┐
│ ┌─────┐ ┌─────┐ │
│ │nginx│ │ log  │ │  ← log collector sidecar
│ │     │ │agent │ │
│ └─────┘ └─────┘ │
│   shared network │
│   shared storage │
└──────────────────┘
```

Don't worry about multi-container pods for now. We'll keep it simple.

---

## Creating Your First Pod

### Method 1: Imperative Command (Quick, for testing)

```bash
# Create a pod running nginx
kubectl run mynginx --image=nginx:latest

# Verify it's running
kubectl get pods
```

### Method 2: Declarative YAML (Recommended for real work)

Create a file called `pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mynginx
  labels:
    app: web
spec:
  containers:
  - name: nginx-container
    image: nginx:latest
    ports:
      - containerPort: 80
```

**Let's break down every line:**

| Line | Meaning |
|------|---------|
| `apiVersion: v1` | Which K8s API to use. Pods use `v1` |
| `kind: Pod` | What type of resource we're creating |
| `metadata.name` | Name of the pod (must be unique) |
| `metadata.labels` | Key-value tags for organizing/selecting pods |
| `spec.containers` | List of containers to run in this pod |
| `name: nginx-container` | Name of the container (for identification) |
| `image: nginx:latest` | Docker image to use |
| `ports.containerPort` | Port the container listens on |

```bash
# Create the pod from YAML
kubectl apply -f pod.yaml

# Check if it's running
kubectl get pods
```

**Expected output:**
```
NAME      READY   STATUS    RESTARTS   AGE
mynginx   1/1     Running   0          30s
```

---

## Pod Lifecycle

A pod goes through these states:

```
Pending → ContainerCreating → Running → Succeeded/Failed
                                          │
                                          └→ CrashLoopBackOff (if container keeps crashing)
```

| State | Meaning |
|-------|---------|
| **Pending** | Pod accepted but image not pulled yet |
| **ContainerCreating** | Image is being pulled and container is starting |
| **Running** | Container is running and healthy |
| **Succeeded** | Container finished its job (for Jobs) |
| **Failed** | Container exited with an error |
| **CrashLoopBackOff** | Container crashes repeatedly, K8s waits before retrying |

---

## Essential Pod Commands

```bash
# List all pods
kubectl get pods

# List pods with more details (IP, Node)
kubectl get pods -o wide

# Detailed information about a specific pod
kubectl describe pod mynginx

# View pod logs
kubectl logs mynginx

# Follow logs in real-time
kubectl logs -f mynginx

# Execute a command inside the pod
kubectl exec mynginx -- ls /usr/share/nginx/html

# Get an interactive shell inside the pod
kubectl exec -it mynginx -- /bin/bash

# Delete a pod
kubectl delete pod mynginx

# Delete pod using YAML file
kubectl delete -f pod.yaml
```

---

## Let's Experiment! (Very Important)

### Experiment 1: See self-healing (Spoiler: Pods DON'T self-heal!)

```bash
# Create a pod
kubectl run testpod --image=nginx

# Delete it
kubectl delete pod testpod

# Check - it's gone forever!
kubectl get pods
# No pods! Pods alone do NOT restart.
```

**This is why we need ReplicaSets and Deployments (Day 05 & 06)**

### Experiment 2: Access your app

```bash
# Forward pod port to your laptop
kubectl port-forward mynginx 8080:80

# Now open browser: http://localhost:8080
# You'll see the nginx welcome page!
# Press Ctrl+C to stop port-forwarding
```

### Experiment 3: Look inside the pod

```bash
# Get a shell inside the container
kubectl exec -it mynginx -- /bin/bash

# Inside the container:
cat /usr/share/nginx/html/index.html
hostname
exit
```

---

## Pod YAML with More Options

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  labels:
    app: web
    environment: dev
spec:
  containers:
  - name: myapp-container
    image: nginx:1.25
    ports:
      - containerPort: 80
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
    env:
      - name: APP_ENV
        value: "development"
```

**New fields explained:**
- `resources.requests` - Minimum resources the container needs
- `resources.limits` - Maximum resources the container can use
- `env` - Environment variables passed to the container
- `250m` CPU = 0.25 CPU cores

---

## Key Takeaways

1. **Pod = smallest unit** in Kubernetes (wraps containers)
2. **Usually 1 container per pod**
3. **Pods are temporary** - they don't restart themselves
4. **Use YAML files** for creating pods (declarative approach)
5. **Labels** are important - they help identify and group pods
6. **Pods alone are NOT enough** for production → we need ReplicaSets/Deployments

---

## Practice / Homework

1. Create a pod running `nginx:latest` using YAML
2. Run `kubectl describe pod` and read every section
3. Use `kubectl exec` to get inside the pod and explore
4. Use `kubectl port-forward` to access nginx in your browser
5. Delete the pod and verify it doesn't come back
6. Create a pod with environment variables and verify with:
   ```bash
   kubectl exec <pod-name> -- env
   ```

---

**Previous:** [← Day 03 - Setup](../Day03-Setup/notes.md)
**Next:** [Day 05 - ReplicaSets →](../Day05-ReplicaSets/notes.md)
