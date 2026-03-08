# Day 18 - Ingress Demo

> **Pre-requisite:** Make sure you've read [Day 17 - Ingress Theory](../day17-ingress/notes.md)
>
> **For production demos on EKS:** See [Ingress Demo (EKS / Production - AWS ALB)](eks-demo.md)

In this hands-on session, we'll set up an nginx Ingress Controller on Minikube and walk through path-based routing, host-based routing, and TLS setup.

---

## Demo Setup - Install nginx Ingress Controller on Minikube

Before we can use Ingress, we need an Ingress Controller. Minikube makes this easy with a built-in addon.

```
┌──── Minikube Cluster ────────────────────────────────────┐
│                                                           │
│  ┌── ingress-nginx namespace ──────────────────────────┐ │
│  │                                                      │ │
│  │  ┌─────────────────────────────────────┐            │ │
│  │  │  nginx Ingress Controller (Pod)     │            │ │
│  │  │  - Watches for Ingress resources    │            │ │
│  │  │  - Configures nginx reverse proxy   │            │ │
│  │  │  - Routes external traffic          │            │ │
│  │  └─────────────────────────────────────┘            │ │
│  │                                                      │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

### Step 1: Enable the Ingress Addon

```bash
# Enable the ingress addon in Minikube
minikube addons enable ingress
# * Verifying ingress addon...
# * The 'ingress-nginx' addon is enabled

# Wait for the controller to be ready (takes ~1 minute)
kubectl get pods -n ingress-nginx -w
# NAME                                        READY   STATUS    RESTARTS   AGE
# ingress-nginx-controller-5d88495688-abcde   1/1     Running   0          60s

# Verify the controller service
kubectl get svc -n ingress-nginx
# NAME                                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
# ingress-nginx-controller             NodePort    10.96.xxx.xxx   <none>        80:xxxxx/TCP,443:xxxxx/TCP   60s
```

### Step 2: Get Minikube IP

```bash
# Minikube IP is needed to access Ingress from your machine
minikube ip
# 192.168.49.2
```

We'll use this IP throughout the demos.

---

## Demo 1 - Path-Based Routing

**Goal:** Route `/app1` to one service and `/app2` to another service, using a single Ingress.

```
Browser request                    Ingress Controller              Backend
                                                                    Services
http://myapp.local/app1  ────►  ┌─────────────────┐  ────►  app1-service ──► app1 pods
                                │  nginx Ingress   │
http://myapp.local/app2  ────►  │  Controller      │  ────►  app2-service ──► app2 pods
                                └─────────────────┘
```

### Step 1: Create Two Deployments and Services

```yaml
# app1-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
      - name: app1
        image: hashicorp/http-echo        # ← Simple HTTP echo server
        args:
        - "-text=Hello from App1!"        # ← Returns this text
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app1-service
spec:
  selector:
    app: app1
  ports:
  - port: 80
    targetPort: 5678
```

```yaml
# app2-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app2
  template:
    metadata:
      labels:
        app: app2
    spec:
      containers:
      - name: app2
        image: hashicorp/http-echo
        args:
        - "-text=Hello from App2!"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app2-service
spec:
  selector:
    app: app2
  ports:
  - port: 80
    targetPort: 5678
```

```bash
# Apply both deployments and services
kubectl apply -f app1-deployment.yaml
kubectl apply -f app2-deployment.yaml

# Verify everything is running
kubectl get deployments
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# app1   2/2     2            2           10s
# app2   2/2     2            2           10s

kubectl get services
# NAME           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
# app1-service   ClusterIP   10.96.100.101    <none>        80/TCP    10s
# app2-service   ClusterIP   10.96.100.102    <none>        80/TCP    10s
```

### Step 2: Create the Path-Based Ingress

```yaml
# path-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /    # ← Important! Rewrites /app1 to /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.local                                # ← Our test hostname
    http:
      paths:
      - path: /app1                                  # ← myapp.local/app1
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80

      - path: /app2                                  # ← myapp.local/app2
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 80
```

```bash
kubectl apply -f path-ingress.yaml
# ingress.networking.k8s.io/path-ingress created

# Check the Ingress
kubectl get ingress
# NAME           CLASS   HOSTS         ADDRESS        PORTS   AGE
# path-ingress   nginx   myapp.local   192.168.49.2   80      10s

# See the detailed rules
kubectl describe ingress path-ingress
# Rules:
#   Host         Path  Backends
#   ----         ----  --------
#   myapp.local
#                /app1   app1-service:80 (10.244.0.5:5678,10.244.0.6:5678)
#                /app2   app2-service:80 (10.244.0.7:5678,10.244.0.8:5678)
```

### Step 3: Add Host Entry and Test

Since `myapp.local` is not a real domain, we need to add it to our `/etc/hosts` file (or `C:\Windows\System32\drivers\etc\hosts` on Windows).

```bash
# Get the Minikube IP
MINIKUBE_IP=$(minikube ip)

# Add host entry (Linux/Mac)
echo "$MINIKUBE_IP myapp.local" | sudo tee -a /etc/hosts

# On Windows (run as Administrator in PowerShell):
# Add-Content C:\Windows\System32\drivers\etc\hosts "$MINIKUBE_IP myapp.local"
```

### Step 4: Test the Routing

```bash
# Test /app1 - should show "Hello from App1!"
curl http://myapp.local/app1
# Hello from App1!

# Test /app2 - should show "Hello from App2!"
curl http://myapp.local/app2
# Hello from App2!

# Test root path - should get 404 (no rule for /)
curl http://myapp.local/
# <html>
# <head><title>404 Not Found</title></head>
# ...

# You can also use the Minikube IP directly with Host header
curl -H "Host: myapp.local" http://$(minikube ip)/app1
# Hello from App1!
```

### Understanding rewrite-target

Without `rewrite-target: /`, the Ingress forwards the **full path** to the backend:
- Request: `/app1` -> Backend receives: `/app1` (service may not handle this path)

With `rewrite-target: /`:
- Request: `/app1` -> Backend receives: `/` (the path is rewritten)
- Request: `/app1/health` -> Backend receives: `/health`

```
Without rewrite:                     With rewrite-target: /

Client: /app1/data                   Client: /app1/data
         │                                    │
         ▼                                    ▼
Backend gets: /app1/data             Backend gets: /data
(usually 404!)                       (works correctly!)
```

### Clean Up Demo 1

```bash
kubectl delete ingress path-ingress
kubectl delete -f app1-deployment.yaml
kubectl delete -f app2-deployment.yaml
```

---

## Demo 2 - Host-Based Routing

**Goal:** Route `app1.example.com` to one service and `app2.example.com` to another.

```
app1.example.com  ────►  ┌──────────────────┐  ────►  app1-service ──► app1 pods
                          │  nginx Ingress   │
app2.example.com  ────►  │  Controller      │  ────►  app2-service ──► app2 pods
                          └──────────────────┘
```

### Step 1: Create Deployments and Services

We'll reuse similar apps but with different names:

```yaml
# host-apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
      - name: app1
        image: hashicorp/http-echo
        args: ["-text=Welcome to App1 (app1.example.com)"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app1-service
spec:
  selector:
    app: app1
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app2
  template:
    metadata:
      labels:
        app: app2
    spec:
      containers:
      - name: app2
        image: hashicorp/http-echo
        args: ["-text=Welcome to App2 (app2.example.com)"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app2-service
spec:
  selector:
    app: app2
  ports:
  - port: 80
    targetPort: 5678
```

```bash
kubectl apply -f host-apps.yaml
# deployment.apps/app1 created
# service/app1-service created
# deployment.apps/app2 created
# service/app2-service created
```

### Step 2: Create the Host-Based Ingress

```yaml
# host-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: app1.example.com            # ← First virtual host
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80

  - host: app2.example.com            # ← Second virtual host
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 80
```

```bash
kubectl apply -f host-ingress.yaml
# ingress.networking.k8s.io/host-ingress created

kubectl get ingress
# NAME           CLASS   HOSTS                                ADDRESS        PORTS   AGE
# host-ingress   nginx   app1.example.com,app2.example.com   192.168.49.2   80      5s
```

### Step 3: Add Host Entries

```bash
# Add both hostnames to /etc/hosts
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP app1.example.com app2.example.com" | sudo tee -a /etc/hosts

# On Windows (run as Administrator in PowerShell):
# Add-Content C:\Windows\System32\drivers\etc\hosts "$MINIKUBE_IP app1.example.com app2.example.com"
```

### Step 4: Test Host-Based Routing

```bash
# Request to app1.example.com
curl http://app1.example.com
# Welcome to App1 (app1.example.com)

# Request to app2.example.com
curl http://app2.example.com
# Welcome to App2 (app2.example.com)

# You can also use -H flag to set the Host header
curl -H "Host: app1.example.com" http://$(minikube ip)
# Welcome to App1 (app1.example.com)

curl -H "Host: app2.example.com" http://$(minikube ip)
# Welcome to App2 (app2.example.com)
```

Same IP address, different responses based on the **hostname**!

### How Does This Work?

```
1. Browser sends request to app1.example.com
2. DNS resolves to Minikube IP (via /etc/hosts)
3. HTTP request includes header: "Host: app1.example.com"
4. Ingress Controller reads the Host header
5. Matches rule: host=app1.example.com -> app1-service
6. Forwards traffic to app1-service
7. app1-service sends to app1 pods

   ┌──── HTTP Request ────────────────┐
   │ GET / HTTP/1.1                    │
   │ Host: app1.example.com   ◄── Key!│
   │ ...                               │
   └───────────────────────────────────┘
```

### Clean Up Demo 2

```bash
kubectl delete ingress host-ingress
kubectl delete -f host-apps.yaml
```

---

## Demo 3 - TLS/HTTPS Setup with Self-Signed Certificate

**Goal:** Secure Ingress with HTTPS using a self-signed TLS certificate.

```
Client                          Ingress Controller              Service
  │                                    │                            │
  │── HTTPS (port 443) ──────────►     │                            │
  │   encrypted with TLS cert          │── HTTP (port 80) ──────►  │
  │                                    │   plain internal traffic   │
  │   Certificate: tls-secret          │                            │
  │   (stored as K8s Secret)           │                            │
```

### Step 1: Create a Self-Signed Certificate

```bash
# Generate a self-signed TLS certificate
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/CN=secure.example.com/O=MyOrg"

# Verify the certificate
openssl x509 -in tls.crt -text -noout | head -15
# Certificate:
#     Data:
#         Version: 3 (0x2)
#         ...
#         Issuer: CN = secure.example.com, O = MyOrg
#         Subject: CN = secure.example.com, O = MyOrg
```

### Step 2: Create a Kubernetes TLS Secret

```bash
# Create the TLS secret from the certificate and key
kubectl create secret tls tls-secret \
  --cert=tls.crt \
  --key=tls.key
# secret/tls-secret created

# Verify the secret was created
kubectl get secrets tls-secret
# NAME         TYPE                DATA   AGE
# tls-secret   kubernetes.io/tls   2      5s

# Inspect the secret
kubectl describe secret tls-secret
# Name:         tls-secret
# Type:         kubernetes.io/tls
# Data:
#   tls.crt:  1164 bytes
#   tls.key:  1704 bytes
```

### Step 3: Create a Test Application

```yaml
# tls-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      containers:
      - name: secure-app
        image: hashicorp/http-echo
        args: ["-text=Hello from HTTPS! Connection is secure."]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: secure-service
spec:
  selector:
    app: secure-app
  ports:
  - port: 80
    targetPort: 5678
```

```bash
kubectl apply -f tls-app.yaml
# deployment.apps/secure-app created
# service/secure-service created
```

### Step 4: Create the Ingress with TLS

```yaml
# tls-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"    # ← Force HTTPS
spec:
  ingressClassName: nginx
  tls:                                                    # ← TLS config section
  - hosts:
    - secure.example.com                                  # ← Domain for this cert
    secretName: tls-secret                                # ← Secret with cert+key
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: secure-service
            port:
              number: 80
```

```bash
kubectl apply -f tls-ingress.yaml
# ingress.networking.k8s.io/tls-ingress created

kubectl get ingress
# NAME          CLASS   HOSTS                ADDRESS        PORTS     AGE
# tls-ingress   nginx   secure.example.com   192.168.49.2   80, 443   5s
#                                                            ^^^^^^^^
#                                                            Note: port 443 is now listed!
```

### Step 5: Add Host Entry and Test

```bash
# Add host entry
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP secure.example.com" | sudo tee -a /etc/hosts

# Test HTTPS (use -k to skip certificate verification for self-signed certs)
curl -k https://secure.example.com
# Hello from HTTPS! Connection is secure.

# Test HTTP - should redirect to HTTPS (because ssl-redirect annotation)
curl -v http://secure.example.com 2>&1 | grep -i location
# < Location: https://secure.example.com/

# Follow the redirect
curl -kL http://secure.example.com
# Hello from HTTPS! Connection is secure.

# Verify the certificate details
curl -kv https://secure.example.com 2>&1 | grep -i "subject\|issuer"
# *  subject: O=MyOrg; CN=secure.example.com
# *  issuer: O=MyOrg; CN=secure.example.com
```

### What Happened?

```
1. curl sends HTTPS request to secure.example.com
2. Ingress Controller presents the TLS certificate from tls-secret
3. TLS handshake completes (curl uses -k to accept self-signed cert)
4. Encrypted traffic reaches Ingress Controller
5. Ingress Controller decrypts it (TLS termination)
6. Forwards plain HTTP to secure-service internally
7. Response travels back through the encrypted channel

   ┌── External Network ──┐    ┌── Inside Cluster ──┐
   │                       │    │                     │
   │  HTTPS (encrypted)    │    │  HTTP (plain)       │
   │  Client ──► Ingress   │    │  Ingress ──► Svc    │
   │             Controller │    │                     │
   └───────────────────────┘    └─────────────────────┘
```

### Clean Up Demo 3

```bash
kubectl delete ingress tls-ingress
kubectl delete -f tls-app.yaml
kubectl delete secret tls-secret
rm tls.crt tls.key
```

---

## Demo 4 - Complete Example (Path + Host + TLS)

**Goal:** Combine everything - multiple hosts, path-based routing, and TLS in one Ingress.

```
                         ┌──────────────────────────┐
                         │   Ingress Controller     │
                         │                          │
https://web.mysite.com   │  web.mysite.com/         │──► frontend-svc
                    ────►│                          │
                         │  api.mysite.com/v1       │──► api-v1-svc
https://api.mysite.com   │                          │
                    ────►│  api.mysite.com/v2       │──► api-v2-svc
                         │                          │
                         └──────────────────────────┘
```

### Step 1: Create All Applications

```yaml
# complete-demo.yaml
# Frontend app
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: hashicorp/http-echo
        args: ["-text=Frontend - web.mysite.com"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 5678
---
# API v1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-v1
  template:
    metadata:
      labels:
        app: api-v1
    spec:
      containers:
      - name: api-v1
        image: hashicorp/http-echo
        args: ["-text=API Version 1 - api.mysite.com/v1"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-v1-svc
spec:
  selector:
    app: api-v1
  ports:
  - port: 80
    targetPort: 5678
---
# API v2
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-v2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-v2
  template:
    metadata:
      labels:
        app: api-v2
    spec:
      containers:
      - name: api-v2
        image: hashicorp/http-echo
        args: ["-text=API Version 2 - api.mysite.com/v2"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-v2-svc
spec:
  selector:
    app: api-v2
  ports:
  - port: 80
    targetPort: 5678
```

```bash
kubectl apply -f complete-demo.yaml
# deployment.apps/frontend created
# service/frontend-svc created
# deployment.apps/api-v1 created
# service/api-v1-svc created
# deployment.apps/api-v2 created
# service/api-v2-svc created
```

### Step 2: Create TLS Certificates

```bash
# Generate certificate for both domains (using SAN)
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout mysite.key \
  -out mysite.crt \
  -subj "/CN=mysite.com" \
  -addext "subjectAltName=DNS:web.mysite.com,DNS:api.mysite.com"

# Create TLS Secret
kubectl create secret tls mysite-tls \
  --cert=mysite.crt \
  --key=mysite.key
```

### Step 3: Create the Combined Ingress

```yaml
# complete-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: complete-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - web.mysite.com
    - api.mysite.com
    secretName: mysite-tls
  rules:
  # Frontend - web.mysite.com
  - host: web.mysite.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80

  # API - api.mysite.com with versioned paths
  - host: api.mysite.com
    http:
      paths:
      - path: /v1
        pathType: Prefix
        backend:
          service:
            name: api-v1-svc
            port:
              number: 80
      - path: /v2
        pathType: Prefix
        backend:
          service:
            name: api-v2-svc
            port:
              number: 80
```

```bash
kubectl apply -f complete-ingress.yaml

# Add host entries
MINIKUBE_IP=$(minikube ip)
echo "$MINIKUBE_IP web.mysite.com api.mysite.com" | sudo tee -a /etc/hosts
```

### Step 4: Test Everything

```bash
# Test frontend
curl -k https://web.mysite.com
# Frontend - web.mysite.com

# Test API v1
curl -k https://api.mysite.com/v1
# API Version 1 - api.mysite.com/v1

# Test API v2
curl -k https://api.mysite.com/v2
# API Version 2 - api.mysite.com/v2

# Test HTTP redirect to HTTPS
curl -v http://web.mysite.com 2>&1 | grep -i location
# < Location: https://web.mysite.com/
```

### Clean Up Demo 4

```bash
kubectl delete ingress complete-ingress
kubectl delete -f complete-demo.yaml
kubectl delete secret mysite-tls
rm mysite.crt mysite.key
```

---

## Troubleshooting Common Issues

### 1. Ingress Address is Empty

```bash
kubectl get ingress
# NAME           CLASS   HOSTS         ADDRESS   PORTS   AGE
# my-ingress     nginx   myapp.com               80      5m

# Fix: Check if Ingress Controller is running
kubectl get pods -n ingress-nginx
# If no pods, the controller is not installed!
minikube addons enable ingress
```

### 2. 404 Not Found

```bash
# Check if services exist and have endpoints
kubectl get svc
kubectl get endpoints

# Check Ingress rules
kubectl describe ingress <name>

# Common cause: service name or port mismatch in Ingress YAML
```

### 3. 503 Service Unavailable

```bash
# Backend pods are not running or not ready
kubectl get pods
# NAME        READY   STATUS             RESTARTS   AGE
# app1-xxx    0/1     CrashLoopBackOff   3          2m

# Fix: Check pod logs
kubectl logs <pod-name>
```

### 4. Cannot Access via Hostname

```bash
# Check /etc/hosts has the correct entry
cat /etc/hosts | grep myapp

# Check Minikube IP hasn't changed
minikube ip

# Try using IP directly with Host header
curl -H "Host: myapp.com" http://$(minikube ip)/path
```

### 5. TLS Certificate Issues

```bash
# Check if the TLS secret exists
kubectl get secrets | grep tls

# Check certificate details
kubectl get secret tls-secret -o jsonpath='{.data.tls\.crt}' | base64 --decode | openssl x509 -text -noout

# Ensure the hostname in the cert matches the Ingress host
```

---

## Useful Debugging Commands

```bash
# Check Ingress Controller logs (very helpful for debugging)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Check Ingress resource details
kubectl describe ingress <ingress-name>

# Check if backend endpoints exist
kubectl get endpoints <service-name>

# Test from inside the cluster
kubectl run test --image=busybox --rm -it -- wget -qO- http://app1-service

# Check nginx configuration generated by the controller
kubectl exec -n ingress-nginx <controller-pod> -- cat /etc/nginx/nginx.conf
```

---

## Key Takeaways

1. **Minikube** has a built-in nginx Ingress addon - just run `minikube addons enable ingress`
2. **Path-based routing** uses `rewrite-target` annotation to strip the path prefix
3. **Host-based routing** requires `/etc/hosts` entries (or real DNS) for testing
4. **TLS setup** requires a Kubernetes Secret of type `kubernetes.io/tls` with `tls.crt` and `tls.key`
5. The `ssl-redirect: "true"` annotation forces HTTP to HTTPS redirection
6. You can **combine** path-based, host-based, and TLS in a single Ingress resource
7. Always check `kubectl describe ingress` and controller logs when troubleshooting
8. Use `curl -k` for self-signed certificates and `curl -H "Host: ..."` for testing without DNS

---

## Practice / Homework

1. Enable the Ingress addon on Minikube and verify the controller is running
2. Create two apps and route `/app1` and `/app2` to them using path-based Ingress
3. Create two apps and route `app1.example.com` and `app2.example.com` using host-based Ingress
4. Generate a self-signed TLS certificate and secure an Ingress with HTTPS
5. Test HTTP to HTTPS redirect using `curl -v`
6. Combine path-based and host-based routing in a single Ingress resource
7. Practice troubleshooting: intentionally break something (wrong service name, wrong port) and debug it

---

**Previous:** [← Day 17 - Ingress (Theory)](../day17-ingress/notes.md)
**Next:** [Day 19 - DaemonSets, Jobs & CronJobs →](../day19-daemonsets-jobs-cronjobs/notes.md)
