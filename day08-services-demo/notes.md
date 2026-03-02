                                # Day 08 - Services Demo (Hands-On Lab)

> **Pre-requisite:** Make sure you've read [Day 07 - Services Theory](../day07-services/notes.md)

In this demo, we'll create all 5 types of Kubernetes Services and test each one step by step.

---

## Setup - Create a Deployment First

We need pods running before we can create services for them.

```bash
# Make sure minikube is running
minikube start

# Create a deployment with 3 replicas
kubectl create deployment web --image=nginx:1.27 --replicas=3

# Verify pods are running
kubectl get pods -o wide --show-labels

# Note: all pods have the label "app=web" (auto-created by deployment)
```

---

## Demo 1: ClusterIP Service (Internal Only)

**Goal:** Create a service accessible ONLY from inside the cluster.

### Step 1: Create the ClusterIP Service

```yaml
# clusterip-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: web-clusterip
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f clusterip-svc.yaml
```

### Step 2: Inspect the Service

```bash
# See the service and its ClusterIP
kubectl get svc web-clusterip
# NAME             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
# web-clusterip    ClusterIP   10.96.45.23    <none>        80/TCP    10s

# See which pods are behind this service (endpoints)
kubectl get endpoints web-clusterip
# NAME             ENDPOINTS                                    AGE
# web-clusterip    10.244.0.5:80,10.244.0.6:80,10.244.0.7:80   10s

# Compare with pod IPs
kubectl get pods -o wide
# Notice: endpoint IPs = pod IPs!
```

### Step 3: Test from INSIDE the cluster

```bash
# Create a temporary test pod and curl the service
kubectl run test-pod --image=busybox --rm -it --restart=Never -- wget -qO- http://web-clusterip
# You should see the nginx HTML page!

# Test using the full DNS name
kubectl run test-pod2 --image=busybox --rm -it --restart=Never -- wget -qO- http://web-clusterip.default.svc.cluster.local
# Same result!
```

### Step 4: Test from OUTSIDE the cluster

```bash
# Try to access ClusterIP from your laptop - THIS WILL FAIL!
curl http://10.96.45.23    # Connection refused / timeout
# ClusterIP is ONLY accessible from inside the cluster!
```

### Step 5: Test Load Balancing

```bash
# Add unique content to each pod so we can see load balancing
for pod in $(kubectl get pods -l app=web -o name); do
  kubectl exec $pod -- bash -c "echo 'Response from: $(hostname)' > /usr/share/nginx/html/index.html"
done

# Hit the service multiple times - notice different pods respond!
for i in 1 2 3 4 5 6; do
  kubectl run test-$i --image=busybox --rm -it --restart=Never -- wget -qO- http://web-clusterip 2>/dev/null
done
# You'll see different hostnames = load balancing is working!
```

### Cleanup

```bash
kubectl delete svc web-clusterip
```

---

## Demo 2: NodePort Service (External Access via Node Port)

**Goal:** Access your app from OUTSIDE the cluster using the Node's IP.

### Step 1: Create the NodePort Service

```yaml
# nodeport-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80            # Service port (internal)
      targetPort: 80      # Container port
      nodePort: 30080     # External port (30000-32767)
```

```bash
kubectl apply -f nodeport-svc.yaml
```

### Step 2: Inspect

```bash
kubectl get svc web-nodeport
# NAME           TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# web-nodeport   NodePort   10.96.12.34   <none>        80:30080/TCP   10s
#                                                        ↑     ↑
#                                                    service  node
#                                                     port    port
```

### Step 3: Access from OUTSIDE the cluster

```bash
# Get the Minikube Node IP
minikube ip
# Example output: 192.168.49.2

# Access using NodeIP:NodePort
curl http://$(minikube ip):30080
# You should see nginx page!

# OR use minikube's shortcut
minikube service web-nodeport --url
# Opens in browser automatically!
```

### Step 4: Understand the 3 Ports

```bash
# Let's see all 3 ports in action:
kubectl describe svc web-nodeport

# Port:        80/TCP        ← Service port (other pods use this)
# TargetPort:  80/TCP        ← Container port (where nginx listens)
# NodePort:    30080/TCP     ← Node port (external access)

# Traffic flow:
# Browser → NodeIP:30080 → Service:80 → Pod:80
```

### Cleanup

```bash
kubectl delete svc web-nodeport
```

---

## Demo 3: LoadBalancer Service (Cloud Load Balancer)

**Goal:** Get an external IP from a cloud load balancer.

### Step 1: Create the LoadBalancer Service

```yaml
# loadbalancer-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: web-lb
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f loadbalancer-svc.yaml
```

### Step 2: Check Status

```bash
kubectl get svc web-lb
# NAME     TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
# web-lb   LoadBalancer   10.96.78.90   <pending>     80:31234/TCP   10s
#                                        ↑
#                                   Pending = no cloud LB available

# On Minikube, use tunnel to simulate a cloud LB:
# Open a NEW terminal and run:
minikube tunnel

# Now check again in original terminal:
kubectl get svc web-lb
# NAME     TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)        AGE
# web-lb   LoadBalancer   10.96.78.90   127.0.0.1      80:31234/TCP   30s
#                                        ↑
#                                   Now has an external IP!
```

### Step 3: Access

```bash
# Access via the external IP
curl http://127.0.0.1
# nginx welcome page!

# In real cloud (AWS/Azure/GCP), you'd get a real public IP or DNS name
```

### Cleanup

```bash
kubectl delete svc web-lb
# Press Ctrl+C in the minikube tunnel terminal
```

---

## Demo 4: ExternalName Service (DNS Alias)

**Goal:** Create a DNS alias pointing to an external service.

### Step 1: Create ExternalName Service

```yaml
# externalname-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-database
spec:
  type: ExternalName
  externalName: database.example.com    # Points to external DNS
```

```bash
kubectl apply -f externalname-svc.yaml
```

### Step 2: Understand What It Does

```bash
kubectl get svc my-database
# NAME          TYPE           CLUSTER-IP   EXTERNAL-IP            PORT(S)   AGE
# my-database   ExternalName   <none>       database.example.com   <none>    10s

# No ClusterIP! It's just a DNS alias.
# When a pod resolves "my-database", it gets "database.example.com"

# Test DNS resolution
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup my-database
# my-database.default.svc.cluster.local → database.example.com
```

### When to Use ExternalName

```
# Your pods reference "my-database"
# Later you migrate from external DB to in-cluster DB:
# Just change the Service from ExternalName → ClusterIP
# No code changes needed!
```

### Cleanup

```bash
kubectl delete svc my-database
```

---

## Demo 5: Headless Service (No Load Balancing)

**Goal:** Get individual pod IPs instead of one service IP. Used with StatefulSets.

### Step 1: Create Headless Service

```yaml
# headless-svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: web-headless
spec:
  clusterIP: None          # ← This makes it headless!
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f headless-svc.yaml
```

### Step 2: Compare with Regular Service

```bash
# Regular service gives ONE IP:
kubectl get svc web-clusterip   # (if still exists)
# CLUSTER-IP: 10.96.45.23      ← Single IP, load balances behind it

# Headless service gives NO ClusterIP:
kubectl get svc web-headless
# CLUSTER-IP: None               ← No single IP!

# DNS lookup for headless service returns ALL pod IPs:
kubectl run test-dns --image=busybox --rm -it --restart=Never -- nslookup web-headless
# Returns:
# Name: web-headless.default.svc.cluster.local
# Address: 10.244.0.5     ← Pod 1
# Address: 10.244.0.6     ← Pod 2
# Address: 10.244.0.7     ← Pod 3
```

### When to Use Headless

- **StatefulSets** (databases) - need to connect to a SPECIFIC pod
- **Service discovery** - when your app needs to know about ALL pods
- We'll use this in the [StatefulSets Demo (Day 15)](../day15-statefulsets-demo/notes.md)

### Cleanup

```bash
kubectl delete svc web-headless
```

---

## Demo 6: Service Discovery with DNS

**Goal:** Prove that pods can find services using DNS names.

### Step 1: Create two deployments with services

```bash
# Frontend deployment
kubectl create deployment frontend --image=nginx --replicas=2
kubectl expose deployment frontend --port=80

# Backend deployment
kubectl create deployment backend --image=httpd --replicas=2
kubectl expose deployment backend --port=80
```

### Step 2: Test DNS from frontend to backend

```bash
# Get into a frontend pod
kubectl exec -it $(kubectl get pod -l app=frontend -o name | head -1) -- bash

# Inside the pod:
# Using short name (same namespace)
curl http://backend
# ✓ Works! Shows Apache "It works!" page

# Using full DNS name
curl http://backend.default.svc.cluster.local
# ✓ Same result!

# Check DNS
apt update && apt install -y dnsutils
nslookup backend
# Server: 10.96.0.10 (CoreDNS)
# Name: backend.default.svc.cluster.local
# Address: 10.96.X.X

exit
```

### Step 3: Cross-Namespace DNS

```bash
# Create a namespace and deploy a service there
kubectl create namespace other-team
kubectl create deployment api --image=httpd --replicas=1 -n other-team
kubectl expose deployment api --port=80 -n other-team

# From default namespace, access the other namespace service
kubectl run test-cross --image=busybox --rm -it --restart=Never -- wget -qO- http://api.other-team
# ✓ Shows "It works!" - cross-namespace access works!

# Short name won't work across namespaces:
kubectl run test-short --image=busybox --rm -it --restart=Never -- wget -qO- http://api
# ✗ FAILS - "api" alone only works in same namespace
```

---

## Demo 7: Self-Healing with Services

**Goal:** Prove that services keep working even when pods restart.

```bash
# Create a service
kubectl expose deployment web --port=80 --name=web-svc

# Note the current endpoints
kubectl get endpoints web-svc

# In one terminal, continuously hit the service:
kubectl run load --image=busybox --rm -it --restart=Never -- sh -c 'while true; do wget -qO- --timeout=1 http://web-svc 2>/dev/null && echo "OK" || echo "FAIL"; sleep 1; done'

# In another terminal, delete a pod:
kubectl delete pod $(kubectl get pod -l app=web -o name | head -1)

# Watch the first terminal - after a brief blip, traffic continues!
# The service automatically routes to the remaining pods
# And when the replacement pod starts, it joins the service too!
```

---

## Complete Cleanup

```bash
kubectl delete deployment web frontend backend
kubectl delete deployment api -n other-team
kubectl delete svc web-svc frontend backend
kubectl delete svc -n other-team api
kubectl delete namespace other-team
```

---

## Summary: All 5 Service Types

| Type | ClusterIP | Accessible From | Use Case |
|------|-----------|----------------|----------|
| **ClusterIP** | Auto-assigned | Inside cluster only | Internal microservice communication |
| **NodePort** | Auto-assigned | Node IP:30000-32767 | Dev/testing, direct node access |
| **LoadBalancer** | Auto-assigned | Cloud LB public IP | Production in cloud |
| **ExternalName** | None | DNS alias | Pointing to external services |
| **Headless** | None | Individual pod IPs via DNS | StatefulSets, service discovery |

---

**Previous:** [← Day 07 - Services (Theory)](../day07-services/notes.md)
**Next:** [Day 09 - Namespaces →](../day09-namespaces/notes.md)
