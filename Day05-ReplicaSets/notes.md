# Day 05 - ReplicaSets

## Why Do We Need ReplicaSets?

Remember from Day 04: **when a Pod dies, it stays dead.** Nobody brings it back.

In the real world, you need:
- **Multiple copies** of your app (for handling more traffic)
- **Self-healing** (if a pod crashes, someone should create a new one)

That "someone" is the **ReplicaSet**.

---

## What Is a ReplicaSet?

A **ReplicaSet** ensures that a **specified number of pod replicas** are running at any given time.

```
┌───────────── ReplicaSet (replicas: 3) ─────────────┐
│                                                      │
│   ┌─────┐      ┌─────┐      ┌─────┐                │
│   │Pod 1│      │Pod 2│      │Pod 3│                │
│   │nginx│      │nginx│      │nginx│                │
│   └─────┘      └─────┘      └─────┘                │
│                                                      │
│   "I will ALWAYS maintain 3 pods. No more, no less." │
└──────────────────────────────────────────────────────┘
```

### What ReplicaSet Does:

| Situation | What ReplicaSet Does |
|-----------|---------------------|
| You say `replicas: 3` | Creates 3 identical pods |
| A pod crashes | Creates a new pod to replace it (self-healing!) |
| You have 4 pods but want 3 | Terminates 1 extra pod |
| A worker node dies | Creates replacement pods on other nodes |

---

## ReplicaSet YAML

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: test-rs
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

### Breaking Down the YAML:

```
spec:
  replicas: 3              ← "I want 3 pods running"

  selector:                ← "How to FIND my pods"
    matchLabels:
      app: web             ← "Look for pods with label app=web"

  template:                ← "Blueprint for creating new pods"
    metadata:
      labels:
        app: web           ← "Give new pods this label" (MUST match selector!)
    spec:
      containers:          ← "What container to run in each pod"
      - name: nginx
        image: nginx:1.25
```

**Important Rule:** The `selector.matchLabels` MUST match `template.metadata.labels`. Otherwise K8s won't know which pods belong to this ReplicaSet.

---

## How Selector Works

```
ReplicaSet selector: app=web
        │
        ├── Finds Pod with label app=web  ✓ (this is mine)
        ├── Finds Pod with label app=web  ✓ (this is mine)
        ├── Finds Pod with label app=api  ✗ (not mine, ignore)
        └── Only 2 pods found, want 3 → creates 1 more!
```

---

## Hands-On: Let's See Self-Healing

```bash
# Step 1: Create the ReplicaSet
kubectl apply -f replicaset.yaml

# Step 2: See 3 pods running
kubectl get pods
# NAME             READY   STATUS    RESTARTS   AGE
# test-rs-abc12    1/1     Running   0          10s
# test-rs-def34    1/1     Running   0          10s
# test-rs-ghi56    1/1     Running   0          10s

# Step 3: Delete one pod (simulate a crash)
kubectl delete pod test-rs-abc12

# Step 4: Immediately check again
kubectl get pods
# NAME             READY   STATUS    RESTARTS   AGE
# test-rs-xyz99    1/1     Running   0          2s   ← NEW pod created!
# test-rs-def34    1/1     Running   0          60s
# test-rs-ghi56    1/1     Running   0          60s

# The ReplicaSet detected: "I need 3 pods, but only 2 exist"
# So it immediately created a new one!
```

---

## Scaling Up and Down

```bash
# Scale up to 5 replicas
kubectl scale rs test-rs --replicas=5

# Check - you'll see 5 pods
kubectl get pods

# Scale down to 2 replicas
kubectl scale rs test-rs --replicas=2

# Check - extra pods are terminated
kubectl get pods
```

---

## Useful ReplicaSet Commands

```bash
# List all ReplicaSets
kubectl get rs

# Describe a ReplicaSet
kubectl describe rs test-rs

# See which pods belong to a ReplicaSet
kubectl get pods --show-labels

# Delete a ReplicaSet (also deletes its pods)
kubectl delete rs test-rs

# Delete ReplicaSet but keep pods running
kubectl delete rs test-rs --cascade=orphan
```

---

## The Problem with ReplicaSets (Why We Need Deployments)

ReplicaSets are great for self-healing and scaling, BUT they have a major limitation:

### What Happens When You Want to Update Your App?

```
Current: nginx:1.25  →  Want: nginx:1.27
```

If you change the image in the ReplicaSet YAML:

```bash
# Change image to nginx:1.27 and apply
kubectl apply -f replicaset.yaml
```

**The existing pods DON'T get updated!** Only NEW pods will use the new image.

To update, you'd have to manually delete old pods one by one. That's:
- Error-prone
- Causes downtime
- Not scalable

**This is exactly why we need Deployments (Day 06)!**

---

## ReplicaSet vs Pod (Comparison)

| Feature | Pod Alone | Pod with ReplicaSet |
|---------|-----------|-------------------|
| Self-healing | No | Yes |
| Multiple copies | No (manual) | Yes (automatic) |
| Scaling | Manual | `kubectl scale` |
| Rolling updates | No | No (use Deployment) |
| When to use | Testing only | Never directly (use Deployment) |

---

## Key Takeaways

1. **ReplicaSet** = ensures a desired number of pods are always running
2. **Self-healing** = if a pod dies, ReplicaSet creates a replacement
3. **Selector + Labels** = how ReplicaSet finds its pods
4. **Template** = the blueprint used to create new pods
5. **Limitation** = can't do rolling updates → use Deployments instead
6. **In practice, you never create ReplicaSets directly** → Deployments create them for you

---

## Practice / Homework

1. Create a ReplicaSet with 3 replicas
2. Delete a pod and watch the self-healing happen
3. Scale to 5 replicas, then back to 2
4. Try changing the image version - do existing pods update?
5. Run `kubectl describe rs test-rs` and study the Events section
6. Think about: Why is self-healing important in production?

---

**Previous:** [← Day 04 - Pods](../Day04-Pods/notes.md)
**Next:** [Day 06 - Deployments →](../Day06-Deployments/notes.md)
