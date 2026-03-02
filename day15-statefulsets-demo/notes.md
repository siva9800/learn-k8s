# Day 15 - StatefulSets Demo

> **Pre-requisite:** Make sure you've read [Day 14 - StatefulSets Theory](../day14-statefulsets/notes.md)
>
> **For production demos on EKS:** See [StatefulSet Demo (EKS / Production - PostgreSQL)](eks-demo.md)

In this hands-on demo, we'll deploy a StatefulSet step by step and prove every feature we learned in theory: ordered creation, stable network identity, per-pod persistent storage, and data persistence across pod restarts.

---

## What We'll Do

```
Step 1: Create a Headless Service
Step 2: Deploy an nginx StatefulSet with 3 replicas
Step 3: Observe ordered pod creation (0 → 1 → 2)
Step 4: Test stable DNS names via Headless Service
Step 5: Prove each pod has its own persistent storage
Step 6: Scale up and down, observe ordering
Step 7: Delete pods and prove data persists
Step 8: Clean up
```

---

## Step 1: Create the Namespace

Let's work in a dedicated namespace to keep things clean:

```bash
kubectl create namespace sts-demo
```

---

## Step 2: Create the Headless Service

The Headless Service is **required** for StatefulSets. It provides stable DNS names for each pod.

```yaml
# headless-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-headless
  namespace: sts-demo
  labels:
    app: nginx
spec:
  clusterIP: None               # <-- Headless! No virtual IP.
  selector:
    app: nginx
  ports:
  - port: 80
    name: web
```

```bash
kubectl apply -f headless-service.yaml

# Verify
kubectl get svc -n sts-demo
# NAME             TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
# nginx-headless   ClusterIP   None         <none>        80/TCP    5s
#                              ^^^^
#                              No IP assigned -- that's what headless means!
```

---

## Step 3: Deploy the nginx StatefulSet

```yaml
# nginx-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
  namespace: sts-demo
spec:
  serviceName: nginx-headless       # Must match the Headless Service name
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html   # Nginx serves files from here
  volumeClaimTemplates:
  - metadata:
      name: www                      # Each pod gets its own PVC named www-web-{ordinal}
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

```bash
kubectl apply -f nginx-statefulset.yaml
```

---

## Step 4: Observe Ordered Pod Creation

Watch the pods being created one by one:

```bash
kubectl get pods -n sts-demo -w
# NAME    READY   STATUS              RESTARTS   AGE
# web-0   0/1     ContainerCreating   0          2s
# web-0   1/1     Running             0          5s      ← web-0 is ready
# web-1   0/1     Pending             0          0s      ← web-1 starts only now
# web-1   0/1     ContainerCreating   0          1s
# web-1   1/1     Running             0          6s      ← web-1 is ready
# web-2   0/1     Pending             0          0s      ← web-2 starts only now
# web-2   0/1     ContainerCreating   0          1s
# web-2   1/1     Running             0          5s      ← all 3 running!
```

Key observations:
- Pods are created **in order**: web-0, then web-1, then web-2
- Each pod must be **Ready** before the next one is created
- Pod names are **predictable** and **sequential**

```
Timeline:
  web-0: [===Creating===][==Running==]
  web-1:                              [===Creating===][==Running==]
  web-2:                                                            [===Creating===][==Running==]
```

Verify the pods:

```bash
kubectl get pods -n sts-demo -o wide
# NAME    READY   STATUS    RESTARTS   AGE   IP            NODE
# web-0   1/1     Running   0          30s   10.244.0.10   node-1
# web-1   1/1     Running   0          25s   10.244.1.8    node-2
# web-2   1/1     Running   0          20s   10.244.2.6    node-3
```

---

## Step 5: Verify the PersistentVolumeClaims

Each pod should have its own PVC:

```bash
kubectl get pvc -n sts-demo
# NAME        STATUS   VOLUME                                     CAPACITY   ACCESS MODES
# www-web-0   Bound    pvc-abc12345-1234-5678-abcd-123456789abc   1Gi        RWO
# www-web-1   Bound    pvc-def67890-1234-5678-abcd-123456789def   1Gi        RWO
# www-web-2   Bound    pvc-ghi11223-1234-5678-abcd-123456789ghi   1Gi        RWO
```

Notice the naming pattern: `{volumeClaimTemplate.name}-{statefulset.name}-{ordinal}`

```
www-web-0  =  www (template name) + web (StatefulSet name) + 0 (pod ordinal)
www-web-1  =  www + web + 1
www-web-2  =  www + web + 2
```

---

## Step 6: Test Stable Network Identity

### 6a: Check DNS names from inside the cluster

Launch a temporary pod with DNS tools:

```bash
kubectl run dns-test --image=busybox:1.36 -n sts-demo --rm -it -- /bin/sh
```

Inside the pod, run these commands:

```bash
# Look up the Headless Service -- returns ALL pod IPs
nslookup nginx-headless.sts-demo.svc.cluster.local

# Server:    10.96.0.10
# Address:   10.96.0.10:53
#
# Name:      nginx-headless.sts-demo.svc.cluster.local
# Address:   10.244.0.10    ← web-0
# Address:   10.244.1.8     ← web-1
# Address:   10.244.2.6     ← web-2

# Look up individual pods by their stable DNS name
nslookup web-0.nginx-headless.sts-demo.svc.cluster.local
# Address: 10.244.0.10     ← Always reaches web-0!

nslookup web-1.nginx-headless.sts-demo.svc.cluster.local
# Address: 10.244.1.8      ← Always reaches web-1!

nslookup web-2.nginx-headless.sts-demo.svc.cluster.local
# Address: 10.244.2.6      ← Always reaches web-2!

# Connect to a specific pod
wget -qO- web-0.nginx-headless:80
wget -qO- web-1.nginx-headless:80
wget -qO- web-2.nginx-headless:80

exit
```

```
DNS Name Format:
  {pod-name}.{headless-service}.{namespace}.svc.cluster.local

  web-0.nginx-headless.sts-demo.svc.cluster.local  → always web-0
  web-1.nginx-headless.sts-demo.svc.cluster.local  → always web-1
  web-2.nginx-headless.sts-demo.svc.cluster.local  → always web-2

  These DNS names are STABLE -- they never change even if the pod restarts!
```

---

## Step 7: Prove Per-Pod Persistent Storage

Let's write a unique file to each pod and prove they have separate storage:

### 7a: Write unique data to each pod

```bash
# Write unique content to each pod's nginx directory
kubectl exec web-0 -n sts-demo -- sh -c 'echo "Hello from web-0" > /usr/share/nginx/html/index.html'
kubectl exec web-1 -n sts-demo -- sh -c 'echo "Hello from web-1" > /usr/share/nginx/html/index.html'
kubectl exec web-2 -n sts-demo -- sh -c 'echo "Hello from web-2" > /usr/share/nginx/html/index.html'
```

### 7b: Verify each pod serves its own content

```bash
# Check that each pod has DIFFERENT content
kubectl exec web-0 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-0

kubectl exec web-1 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-1

kubectl exec web-2 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-2
```

This proves each pod has its **own separate storage**. In a Deployment with shared storage, all three would show the same content.

```
Per-Pod Storage Visualization:

  web-0 ──→ /usr/share/nginx/html ──→ PVC www-web-0 ──→ "Hello from web-0"
  web-1 ──→ /usr/share/nginx/html ──→ PVC www-web-1 ──→ "Hello from web-1"
  web-2 ──→ /usr/share/nginx/html ──→ PVC www-web-2 ──→ "Hello from web-2"

  Each pod's volume is INDEPENDENT!
```

---

## Step 8: Scale Up and Observe Ordering

### 8a: Scale up from 3 to 5

```bash
kubectl scale statefulset web -n sts-demo --replicas=5

# Watch the new pods being created IN ORDER
kubectl get pods -n sts-demo -w
# web-0   1/1   Running   0   5m
# web-1   1/1   Running   0   5m
# web-2   1/1   Running   0   5m
# web-3   0/1   Pending   0   0s      ← New! Created after web-2
# web-3   1/1   Running   0   5s
# web-4   0/1   Pending   0   0s      ← New! Created after web-3
# web-4   1/1   Running   0   5s

# Verify new PVCs were created
kubectl get pvc -n sts-demo
# NAME        STATUS   CAPACITY
# www-web-0   Bound    1Gi
# www-web-1   Bound    1Gi
# www-web-2   Bound    1Gi
# www-web-3   Bound    1Gi       ← New!
# www-web-4   Bound    1Gi       ← New!
```

### 8b: Scale down from 5 to 3

```bash
kubectl scale statefulset web -n sts-demo --replicas=3

# Watch pods being deleted in REVERSE order
kubectl get pods -n sts-demo -w
# web-4   1/1   Terminating   0   2m    ← web-4 deleted first!
# web-3   1/1   Terminating   0   2m    ← then web-3
# web-0   1/1   Running       0   7m    ← these three remain
# web-1   1/1   Running       0   7m
# web-2   1/1   Running       0   7m
```

```
Scale Down Order:
  Deleted: web-4 (highest ordinal first)
  Deleted: web-3
  Kept:    web-2, web-1, web-0

  PVCs for web-3 and web-4 still EXIST (data is preserved)
```

```bash
# PVCs for deleted pods still exist!
kubectl get pvc -n sts-demo
# NAME        STATUS   CAPACITY
# www-web-0   Bound    1Gi
# www-web-1   Bound    1Gi
# www-web-2   Bound    1Gi
# www-web-3   Bound    1Gi       ← Still here even though web-3 is gone
# www-web-4   Bound    1Gi       ← Still here even though web-4 is gone
```

---

## Step 9: Delete and Recreate -- Data Persists!

This is the most important test. Let's prove that data survives pod deletion.

### 9a: Delete a specific pod

```bash
# Delete web-1
kubectl delete pod web-1 -n sts-demo

# Watch it come back with the SAME name
kubectl get pods -n sts-demo -w
# web-1   1/1   Terminating   0   8m
# web-1   0/1   Pending       0   0s      ← Same name! web-1 again!
# web-1   1/1   Running       0   4s
```

### 9b: Check that the data is still there

```bash
kubectl exec web-1 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-1       ← DATA SURVIVED the pod deletion!
```

### 9c: Delete the ENTIRE StatefulSet and recreate it

```bash
# Delete the StatefulSet (but NOT the PVCs)
kubectl delete statefulset web -n sts-demo
# All pods are deleted

# Verify pods are gone but PVCs remain
kubectl get pods -n sts-demo
# No resources found

kubectl get pvc -n sts-demo
# NAME        STATUS   CAPACITY
# www-web-0   Bound    1Gi       ← PVCs survived!
# www-web-1   Bound    1Gi
# www-web-2   Bound    1Gi

# Recreate the StatefulSet
kubectl apply -f nginx-statefulset.yaml

# Wait for pods to come up
kubectl get pods -n sts-demo -w
# web-0   1/1   Running   0   5s
# web-1   1/1   Running   0   10s
# web-2   1/1   Running   0   15s
```

### 9d: Verify data survived the full recreation

```bash
kubectl exec web-0 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-0       ← Still there!

kubectl exec web-1 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-1       ← Still there!

kubectl exec web-2 -n sts-demo -- cat /usr/share/nginx/html/index.html
# Hello from web-2       ← Still there!
```

```
Data Persistence Flow:

  1. Pod web-1 writes "Hello from web-1" to PVC www-web-1
  2. Pod web-1 is deleted (or entire StatefulSet is deleted)
  3. PVC www-web-1 remains (data is safe on disk)
  4. StatefulSet is recreated
  5. New web-1 pod is created
  6. web-1 reattaches to PVC www-web-1
  7. "Hello from web-1" is still there!

  ┌───────┐     ┌──────────┐     ┌───────┐
  │ web-1 │ ──→ │ PVC      │ ←── │ web-1 │
  │(old)  │     │ www-web-1│     │(new)  │
  │DELETE │     │ PERSISTS │     │CREATE │
  └───────┘     └──────────┘     └───────┘
```

---

## Step 10: Clean Up

```bash
# Delete everything in the namespace
kubectl delete namespace sts-demo

# This deletes:
# - StatefulSet (and all pods)
# - Headless Service
# - PVCs (and their bound PVs)

# Verify cleanup
kubectl get all -n sts-demo
# No resources found
```

Alternatively, delete things individually:

```bash
# Delete StatefulSet
kubectl delete statefulset web -n sts-demo

# Delete PVCs (this actually deletes the data)
kubectl delete pvc www-web-0 www-web-1 www-web-2 -n sts-demo

# Delete the Headless Service
kubectl delete svc nginx-headless -n sts-demo

# Delete the namespace
kubectl delete namespace sts-demo
```

---

## Summary of What We Proved

```
┌───────────────────────────────────────────────────────────────────┐
│  Feature                 │ What We Observed                       │
│──────────────────────────│────────────────────────────────────────│
│  Ordered creation        │ web-0 → web-1 → web-2 (one by one)   │
│  Stable pod names        │ Always web-0, web-1, web-2            │
│  Stable DNS names        │ web-0.nginx-headless always resolves  │
│  Per-pod storage         │ Each pod has its own unique content    │
│  Ordered scale-up        │ web-3, then web-4                     │
│  Reverse scale-down      │ web-4 first, then web-3               │
│  Data persistence        │ Content survived pod deletion          │
│  PVC retention           │ PVCs remain after StatefulSet deletion │
│  Data survives recreate  │ Recreated pods reattach to old PVCs   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Key Takeaways

1. **Headless Service is required** before creating a StatefulSet (set `clusterIP: None`)
2. Pods are created **sequentially** (0, 1, 2) -- each must be Ready before the next starts
3. Each pod gets a **stable DNS name**: `{pod}.{headless-svc}.{namespace}.svc.cluster.local`
4. **volumeClaimTemplates** automatically create a unique PVC for each pod
5. PVC naming: `{template-name}-{statefulset-name}-{ordinal}` (e.g., `www-web-0`)
6. **Data persists** across pod deletion, scaling, and even full StatefulSet deletion
7. PVCs are **never auto-deleted** -- you must remove them manually to free storage
8. Scale-down happens in **reverse order** (highest ordinal first)
9. When a pod is recreated, it **reattaches to its original PVC** -- data is preserved
10. Use `nslookup` or `dig` from a pod to test DNS resolution of StatefulSet pods

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Pod stuck in Pending | No PV available for the PVC | Create a PV or use a StorageClass with dynamic provisioning |
| web-1 not starting | web-0 is not Ready yet | Check web-0 logs: `kubectl logs web-0 -n sts-demo` |
| DNS not resolving | Headless Service missing or wrong `serviceName` | Verify Service exists and `serviceName` in StatefulSet matches |
| Data lost after pod restart | Volume not mounted correctly | Check `volumeMounts` and `volumeClaimTemplates` match |
| PVC stuck in Pending | No StorageClass or PV available | `kubectl describe pvc <name>` to see the error |

---

**Previous:** [<-- Day 14 - StatefulSets (Theory)](../day14-statefulsets/notes.md)
**Next:** [Day 16 - Ingress -->](../day16-ingress/notes.md)
