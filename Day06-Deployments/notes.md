# Day 06 - Deployments

## Why Do We Need Deployments?

From Day 05, we learned that ReplicaSets can:
- Maintain a desired number of pods (self-healing)
- Scale up/down

But ReplicaSets **cannot** do rolling updates. When you change the image version, existing pods don't get updated.

**Deployment** = ReplicaSet + Rolling Updates + Rollbacks

```
┌────────────────── Deployment ──────────────────┐
│                                                 │
│  ┌──────────── ReplicaSet ──────────────┐      │
│  │                                       │      │
│  │   ┌─────┐   ┌─────┐   ┌─────┐       │      │
│  │   │Pod 1│   │Pod 2│   │Pod 3│       │      │
│  │   └─────┘   └─────┘   └─────┘       │      │
│  │                                       │      │
│  └───────────────────────────────────────┘      │
│                                                 │
│  + Rolling Updates                              │
│  + Rollback History                             │
│  + Pause/Resume Updates                         │
└─────────────────────────────────────────────────┘
```

> **In real world, you almost ALWAYS use Deployments. Never create Pods or ReplicaSets directly.**

---

## The Hierarchy

```
Deployment  (you create this)
    │
    └── creates → ReplicaSet  (automatically managed)
                      │
                      └── creates → Pods  (automatically managed)
```

You only interact with the Deployment. K8s handles the rest.

---

## Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deploy
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
```

**Notice:** The YAML looks almost identical to a ReplicaSet. The only difference is `kind: Deployment` instead of `kind: ReplicaSet`.

---

## Creating a Deployment

```bash
# Method 1: Using YAML (recommended)
kubectl apply -f deployment.yaml

# Method 2: Imperative command (quick testing)
kubectl create deployment web-deploy --image=nginx:1.25 --replicas=3
```

### Verify:

```bash
# See the deployment
kubectl get deployments
# NAME          READY   UP-TO-DATE   AVAILABLE   AGE
# web-deploy    3/3     3            3           30s

# See the ReplicaSet it created
kubectl get rs
# NAME                    DESIRED   CURRENT   READY   AGE
# web-deploy-7f8b9c6d5f   3         3         3       30s

# See the pods it created
kubectl get pods
# NAME                          READY   STATUS    RESTARTS   AGE
# web-deploy-7f8b9c6d5f-abc12   1/1     Running   0          30s
# web-deploy-7f8b9c6d5f-def34   1/1     Running   0          30s
# web-deploy-7f8b9c6d5f-ghi56   1/1     Running   0          30s
```

**Notice the naming pattern:**
```
web-deploy  -  7f8b9c6d5f  -  abc12
Deployment     ReplicaSet     Pod
   name          hash         random
```

---

## Rolling Updates (The Killer Feature)

This is WHY you use Deployments. Let's update nginx from `1.25` to `1.27`:

### Method 1: Edit the YAML and apply

```yaml
# Change image in deployment.yaml
image: nginx:1.27  # was nginx:1.25
```

```bash
kubectl apply -f deployment.yaml
```

### Method 2: Command line

```bash
kubectl set image deployment/web-deploy nginx=nginx:1.27
```

### What Happens During a Rolling Update:

```
Step 1: Current state (3 pods with v1.25)
┌─────────┐ ┌─────────┐ ┌─────────┐
│ v1.25   │ │ v1.25   │ │ v1.25   │
└─────────┘ └─────────┘ └─────────┘

Step 2: New pod created with v1.27, old pod terminated
┌─────────┐ ┌─────────┐ ┌─────────┐
│ v1.27 ✓ │ │ v1.25   │ │ v1.25   │
└─────────┘ └─────────┘ └─────────┘

Step 3: Another new pod, another old pod removed
┌─────────┐ ┌─────────┐ ┌─────────┐
│ v1.27 ✓ │ │ v1.27 ✓ │ │ v1.25   │
└─────────┘ └─────────┘ └─────────┘

Step 4: All updated! Zero downtime!
┌─────────┐ ┌─────────┐ ┌─────────┐
│ v1.27 ✓ │ │ v1.27 ✓ │ │ v1.27 ✓ │
└─────────┘ └─────────┘ └─────────┘
```

**Zero downtime!** At no point were all pods down at the same time.

### Watch it happen in real-time:

```bash
# In terminal 1: watch the rollout
kubectl rollout status deployment/web-deploy

# In terminal 2: watch pods
kubectl get pods -w
```

---

## Rollback (Undo a Bad Deployment)

Deployed a buggy version? No problem!

```bash
# Check rollout history
kubectl rollout history deployment/web-deploy

# Roll back to previous version
kubectl rollout undo deployment/web-deploy

# Roll back to a specific revision
kubectl rollout undo deployment/web-deploy --to-revision=1

# Verify
kubectl rollout status deployment/web-deploy
```

### How Rollback Works:

```
Before rollback:
  ReplicaSet-v1 (0 pods)  ← old, scaled down
  ReplicaSet-v2 (3 pods)  ← current

After rollback:
  ReplicaSet-v1 (3 pods)  ← scaled back up!
  ReplicaSet-v2 (0 pods)  ← scaled down
```

K8s keeps old ReplicaSets (with 0 pods) so it can roll back instantly!

---

## Rolling Update Strategy Options

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deploy
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1    # Max pods that can be unavailable during update
      maxSurge: 1           # Max extra pods created during update
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
```

| Strategy | Behavior |
|----------|----------|
| `RollingUpdate` (default) | Gradually replace old pods with new |
| `Recreate` | Kill ALL old pods first, then create new ones (has downtime!) |

| Setting | Meaning |
|---------|---------|
| `maxUnavailable: 1` | At most 1 pod can be down during update |
| `maxSurge: 1` | At most 1 extra pod can be created during update |

---

## Scaling Deployments

```bash
# Scale to 5 replicas
kubectl scale deployment web-deploy --replicas=5

# Verify
kubectl get deployment web-deploy
```

---

## Useful Deployment Commands

```bash
# List all deployments
kubectl get deployments

# Describe a deployment
kubectl describe deployment web-deploy

# See rollout history
kubectl rollout history deployment/web-deploy

# Check rollout status
kubectl rollout status deployment/web-deploy

# Pause a rollout (useful for canary testing)
kubectl rollout pause deployment/web-deploy

# Resume a paused rollout
kubectl rollout resume deployment/web-deploy

# Delete a deployment (also deletes RS and Pods)
kubectl delete deployment web-deploy
```

---

## Pod vs ReplicaSet vs Deployment

| Feature | Pod | ReplicaSet | Deployment |
|---------|-----|------------|------------|
| Run containers | Yes | Yes | Yes |
| Self-healing | No | Yes | Yes |
| Scaling | No | Yes | Yes |
| Rolling updates | No | No | **Yes** |
| Rollback | No | No | **Yes** |
| Use in production | Never alone | Rarely directly | **Always** |

---

## Key Takeaways

1. **Always use Deployments** - never create Pods or ReplicaSets directly
2. **Deployment = ReplicaSet + Updates + Rollbacks**
3. **Rolling updates** give you zero-downtime deployments
4. **Rollback** lets you undo bad deployments instantly
5. K8s keeps old ReplicaSets for rollback history
6. The YAML is almost identical to ReplicaSet (just `kind: Deployment`)

---

## Practice / Homework

1. Create a Deployment with `nginx:1.25` and 3 replicas
2. Update the image to `nginx:1.27` and watch the rolling update
3. Check `kubectl rollout history` to see revisions
4. Roll back to `nginx:1.25` and verify
5. Try `strategy: Recreate` and compare with RollingUpdate
6. Scale up to 5, then back to 2

---

**Previous:** [← Day 05 - ReplicaSets](../Day05-ReplicaSets/notes.md)
**Next:** [Day 07 - Services & Networking →](../Day07-Services/notes.md)
