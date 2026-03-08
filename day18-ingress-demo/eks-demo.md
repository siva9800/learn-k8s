# Day 18 - Ingress Demo (EKS / Production - AWS ALB)

> **Pre-requisites:**
> - [Day 17 - Ingress Theory](../day17-ingress/notes.md)
> - [Day 18 - Ingress Demo (Local / Minikube)](notes.md)
> - A running EKS cluster with the EBS CSI driver working

## Minikube vs EKS Ingress - Key Difference

```
Minikube:
  Ingress Controller = nginx (runs inside cluster as a pod)
  Creates: Nothing outside the cluster
  Access: minikube ip + /etc/hosts

EKS:
  Ingress Controller = AWS Load Balancer Controller (runs inside cluster)
  Creates: REAL AWS Application Load Balancer (ALB) in your AWS account
  Access: ALB DNS name (public URL, real internet access!)
```

```
┌─── Minikube ──────────────────────┐     ┌─── EKS ─────────────────────────────┐
│                                    │     │                                      │
│  Browser --> minikube ip           │     │  Browser --> ALB DNS name            │
│      |                             │     │      |                               │
│      v                             │     │      v                               │
│  nginx pod (inside cluster)        │     │  AWS ALB (outside cluster)           │
│      |                             │     │      |                               │
│      v                             │     │      v                               │
│  Service --> Pods                  │     │  Target Group --> Pods (directly!)   │
│                                    │     │                                      │
└────────────────────────────────────┘     └──────────────────────────────────────┘
```

---

## What Is AWS Load Balancer Controller?

It's a K8s controller that watches for Ingress resources and **automatically creates AWS ALBs**.

```
You create this in K8s:          AWS LB Controller creates this in AWS:
┌──────────────┐                 ┌──────────────────────────┐
│  Ingress     │    -------->    │  Application Load        │
│  YAML        │    auto         │  Balancer (ALB)          │
│              │    creates      │  + Target Groups         │
│  host: ...   │                 │  + Listener Rules        │
│  path: /api  │                 │  + Health Checks         │
└──────────────┘                 └──────────────────────────┘
```

### ALB vs NLB - When to Use Which

| Feature | ALB (Application LB) | NLB (Network LB) |
|---------|----------------------|-------------------|
| **Layer** | Layer 7 (HTTP/HTTPS) | Layer 4 (TCP/UDP) |
| **Created by** | Ingress resource | Service type: LoadBalancer |
| **Routing** | Path-based, host-based | Port-based only |
| **SSL termination** | Yes (with ACM certs) | Yes (with ACM certs) |
| **Use for** | Web apps, APIs, microservices | Databases, gRPC, raw TCP |
| **Cost** | ~$16/month + traffic | ~$16/month + traffic |

```
Rule of thumb:
  HTTP/HTTPS traffic --> Use ALB (via Ingress)
  Everything else    --> Use NLB (via Service type: LoadBalancer)
```

---

## Step 0: Install AWS Load Balancer Controller

This is the **official AWS recommended method** (from [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)).

```
It's NOT an EKS addon (like VPC CNI or EBS CSI driver).
You install it separately using eksctl + Helm.

What gets installed:
  - IAM Policy (what the controller can do in AWS)
  - IAM Role + ServiceAccount via IRSA (who can assume the role)
  - Controller Deployment via Helm (the actual pods)
```

### Step 0a: Create IAM Policy

```bash
# Download the IAM policy (defines what the controller can do in AWS)
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

# Create the policy in AWS
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

### Step 0b: Create IAM Role + K8s ServiceAccount (using eksctl)

```bash
# This ONE command does 3 things:
#   1. Creates an IAM Role with IRSA trust policy
#   2. Attaches the policy to the role
#   3. Creates a K8s ServiceAccount annotated with the role ARN

eksctl create iamserviceaccount \
  --cluster=my-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region ap-south-1 \
  --approve
```

```
What eksctl does behind the scenes:

  AWS Side:
    IAM Role created with OIDC trust policy
    (only this specific EKS service account can assume this role)

  K8s Side:
    ServiceAccount: aws-load-balancer-controller (in kube-system)
    Annotation: eks.amazonaws.com/role-arn = arn:aws:iam::xxx:role/xxx

  This is called IRSA (IAM Roles for Service Accounts).
  The controller pods use this ServiceAccount to get AWS permissions.
```

### Step 0c: Install Controller via Helm

```bash
# Add the EKS Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# Install the controller
# Note: serviceAccount.create=false because eksctl already created it
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=my-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify it's running
kubectl get deployment -n kube-system aws-load-balancer-controller
# NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
# aws-load-balancer-controller   2/2     2            2           60s
```

```
Why serviceAccount.create=false?
  eksctl already created the ServiceAccount (with the IAM role annotation).
  If Helm also creates it, it would overwrite the annotation and break IRSA.
  So we tell Helm: "don't create it, just use the existing one."
```

---

## How Does ALB Know Which Subnet to Use?

We didn't specify any VPC or subnet in the Ingress YAML. So how does the ALB Controller know where to create the ALB?

```
VPC:
  The controller automatically knows the VPC from the EKS cluster config.
  You NEVER need to specify the VPC.

Subnets:
  The controller discovers subnets using TAGS on the subnets.
  When eksctl creates a cluster, it tags the subnets automatically.
```

### Subnet Auto-Discovery (via Tags)

```
When you set:
  alb.ingress.kubernetes.io/scheme: internet-facing

  Controller looks for subnets tagged:
    kubernetes.io/role/elb = 1            (public subnets)

When you set:
  alb.ingress.kubernetes.io/scheme: internal

  Controller looks for subnets tagged:
    kubernetes.io/role/internal-elb = 1   (private subnets)
```

```
Who tags the subnets?

  eksctl   --> Tags subnets automatically when creating the cluster
  Terraform --> You must add the tags yourself in your subnet resource
  Console  --> You must add the tags manually in AWS console
```

### Explicitly Specifying Subnets (Optional)

If auto-discovery doesn't work (missing tags) or you want control over which subnets:

```yaml
annotations:
  alb.ingress.kubernetes.io/subnets: subnet-0abc123, subnet-0def456
```

### Verify Subnet Tags

```bash
# Check if your subnets are tagged correctly
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=<your-vpc-id>" \
  --query 'Subnets[].{ID:SubnetId, AZ:AvailabilityZone, Tags:Tags[?Key==`kubernetes.io/role/elb`]}'

# If tags are missing, add them:
aws ec2 create-tags \
  --resources subnet-0abc123 subnet-0def456 \
  --tags Key=kubernetes.io/role/elb,Value=1
```

```
Summary:
  VPC     --> Controller knows automatically (from EKS cluster)
  Subnets --> Auto-discovered via tags (eksctl does this for you)

  No tags? --> ALB creation fails silently
  Fix:     --> Add tags manually or use the subnets annotation
```

---

## Demo 1 - Basic ALB Ingress (Path-Based Routing)

**Goal:** Create an ALB that routes `/app1` and `/app2` to different services.

```
Internet --> ALB (auto-created) --> /app1 --> app1-service --> app1 pods
                                --> /app2 --> app2-service --> app2 pods
```

### Step 1: Create Apps and Services

```yaml
# eks-ingress-apps.yaml
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
        args: ["-text=Hello from App1!"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app1-service
spec:
  type: NodePort          # ALB Ingress needs NodePort or IP target type
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
        args: ["-text=Hello from App2!"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: app2-service
spec:
  type: NodePort
  selector:
    app: app2
  ports:
  - port: 80
    targetPort: 5678
```

```bash
kubectl apply -f eks-ingress-apps.yaml
```

### Step 2: Create the Ingress (This Creates an ALB!)

```yaml
# eks-path-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-ingress
  annotations:
    # These annotations tell AWS LB Controller what to create
    alb.ingress.kubernetes.io/scheme: internet-facing     # Public ALB
    alb.ingress.kubernetes.io/target-type: instance        # Route to NodePort
    alb.ingress.kubernetes.io/subnets: subnet-0abc123, subnet-0def456   # Your public subnets
spec:
  ingressClassName: alb                                    # <-- "alb" not "nginx"!
  rules:
  - http:
      paths:
      - path: /app1
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80
      - path: /app2
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 80
```

```bash
kubectl apply -f eks-path-ingress.yaml

# Wait 2-3 minutes for ALB to be created in AWS
kubectl get ingress path-ingress
# NAME           CLASS   HOSTS   ADDRESS                                               PORTS   AGE
# path-ingress   alb     *       k8s-default-pathingr-xxxx.ap-south-1.elb.amazonaws.com  80    2m

# That ADDRESS is a REAL public URL!
```

### Step 3: Test It

```bash
# Get the ALB URL
ALB_URL=$(kubectl get ingress path-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Wait for ALB to finish provisioning (health checks take ~30s)
# Then test:
curl http://$ALB_URL/app1
# Hello from App1!

curl http://$ALB_URL/app2
# Hello from App2!
```

### What Happened in AWS?

```bash
# You can see the ALB in AWS console: EC2 --> Load Balancers
# Or via CLI:
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'
```

```
AWS resources created automatically:
  1. ALB (Application Load Balancer)
  2. Target Group for app1 (with EC2 instances as targets)
  3. Target Group for app2
  4. Listener on port 80
  5. Listener Rules: /app1 --> TG1, /app2 --> TG2
  6. Security Group allowing port 80
```

### Clean Up Demo 1

```bash
kubectl delete ingress path-ingress
# This DELETES the ALB from AWS (takes ~1 min)

kubectl delete -f eks-ingress-apps.yaml
```

---

## Demo 2 - Host-Based Routing with ALB

**Goal:** Route `app1.example.com` and `app2.example.com` to different services using a single ALB.

### Step 1: Create Apps (same as Demo 1)

```bash
kubectl apply -f eks-ingress-apps.yaml
```

### Step 2: Create Host-Based Ingress

```yaml
# eks-host-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: subnet-0abc123, subnet-0def456   # Your public subnets
spec:
  ingressClassName: alb
  rules:
  - host: app1.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80
  - host: app2.example.com
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
kubectl apply -f eks-host-ingress.yaml

# Get ALB URL
ALB_URL=$(kubectl get ingress host-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test with Host header (since we don't own example.com)
curl -H "Host: app1.example.com" http://$ALB_URL
# Hello from App1!

curl -H "Host: app2.example.com" http://$ALB_URL
# Hello from App2!
```

### In Production: Use Route 53

```
In real production, you would:

1. Own a domain (e.g., mycompany.com)
2. Create a Route 53 hosted zone
3. Create CNAME/Alias records pointing to the ALB:
   app1.mycompany.com --> ALB DNS name
   app2.mycompany.com --> ALB DNS name

Then users can access:
  http://app1.mycompany.com --> App1
  http://app2.mycompany.com --> App2
```

### Clean Up Demo 2

```bash
kubectl delete ingress host-ingress
kubectl delete -f eks-ingress-apps.yaml
```

---

## Demo 3 - HTTPS with ACM (AWS Certificate Manager)

This is where EKS shines! No self-signed certs needed. AWS gives you **free SSL certificates** via ACM.

```
Minikube TLS:                           EKS TLS:
  Generate self-signed cert               Request FREE cert from ACM
  Create K8s Secret manually              Just add annotation with cert ARN
  Users see "not secure" warning          Users see valid green lock
  Certs expire, manual renewal            ACM auto-renews!
```

### Step 1: Request a Certificate from ACM

```bash
# Request a certificate (you need to own the domain!)
aws acm request-certificate \
  --domain-name "*.mycompany.com" \
  --validation-method DNS \
  --region ap-south-1

# Note the CertificateArn from the output:
# arn:aws:acm:ap-south-1:123456789:certificate/abc-123-def-456

# Validate the certificate via DNS (add the CNAME record ACM gives you to Route 53)
# After validation, certificate status becomes ISSUED
```

### Step 2: Create HTTPS Ingress with ACM Certificate

```yaml
# eks-https-ingress.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web-app
        image: hashicorp/http-echo
        args: ["-text=Hello from HTTPS! Connection is secure."]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  type: NodePort
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: https-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: instance
    alb.ingress.kubernetes.io/subnets: subnet-0abc123, subnet-0def456   # Your public subnets
    # HTTPS annotations
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-south-1:123456789:certificate/abc-123-def-456
    alb.ingress.kubernetes.io/ssl-redirect: "443"    # Redirect HTTP to HTTPS
spec:
  ingressClassName: alb
  rules:
  - host: app.mycompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

```bash
kubectl apply -f eks-https-ingress.yaml

# Get ALB URL
ALB_URL=$(kubectl get ingress https-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo $ALB_URL

# Create Route 53 record: app.mycompany.com --> ALB_URL

# Test (after DNS propagation):
curl https://app.mycompany.com
# Hello from HTTPS! Connection is secure.

# HTTP automatically redirects to HTTPS:
curl -v http://app.mycompany.com 2>&1 | grep Location
# Location: https://app.mycompany.com:443/
```

```
What AWS creates:

ALB:
  Listener port 80  --> Redirect to HTTPS (443)
  Listener port 443 --> Forward to Target Group
                        Uses ACM certificate for SSL

No K8s Secret needed! ACM handles the certificate entirely.
```

### Clean Up Demo 3

```bash
kubectl delete -f eks-https-ingress.yaml
```

---

## Demo 4 - IP Target Type (Pod Direct Routing)

By default, ALB routes to EC2 instances (NodePort). With IP target type, ALB routes **directly to pod IPs** -- faster and no NodePort needed!

```
Instance mode (default):
  ALB --> EC2 NodePort --> kube-proxy --> Pod
  (extra hop through kube-proxy)

IP mode:
  ALB --> Pod IP directly
  (faster, fewer hops, but needs VPC CNI)
```

### When to Use IP Mode

```
Use INSTANCE mode when:
  - Simple setup
  - Don't need maximum performance

Use IP mode when:
  - Want lowest latency
  - Running on Fargate (Fargate REQUIRES IP mode)
  - Want ALB to do health checks directly on pods
```

### IP Mode Ingress

```yaml
# eks-ip-ingress.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fast-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fast-app
  template:
    metadata:
      labels:
        app: fast-app
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args: ["-text=Direct pod routing! No NodePort hop."]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: fast-service
spec:
  type: ClusterIP              # <-- ClusterIP is fine with IP mode! No NodePort needed
  selector:
    app: fast-app
  ports:
  - port: 80
    targetPort: 5678
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ip-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip           # <-- IP mode!
    alb.ingress.kubernetes.io/subnets: subnet-0abc123, subnet-0def456   # Your public subnets
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fast-service
            port:
              number: 80
```

```bash
kubectl apply -f eks-ip-ingress.yaml

# Check target group -- it will show POD IPs, not EC2 IPs
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}'
# [
#   { "Target": "10.244.0.15", "Port": 5678, "Health": "healthy" },  <-- Pod IP!
#   { "Target": "10.244.1.22", "Port": 5678, "Health": "healthy" },  <-- Pod IP!
#   { "Target": "10.244.2.8",  "Port": 5678, "Health": "healthy" }   <-- Pod IP!
# ]
```

### Clean Up Demo 4

```bash
kubectl delete -f eks-ip-ingress.yaml
```

---

## Important ALB Annotations Reference

```yaml
# Commonly used annotations:
annotations:
  # Network
  alb.ingress.kubernetes.io/scheme: internet-facing    # or "internal" for private
  alb.ingress.kubernetes.io/target-type: instance       # or "ip" for direct pod routing

  # HTTPS / TLS
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
  alb.ingress.kubernetes.io/ssl-redirect: "443"

  # Health checks
  alb.ingress.kubernetes.io/healthcheck-path: /healthz
  alb.ingress.kubernetes.io/healthcheck-interval-seconds: "15"
  alb.ingress.kubernetes.io/healthy-threshold-count: "2"

  # Security
  alb.ingress.kubernetes.io/security-groups: sg-xxxx     # Custom security group
  alb.ingress.kubernetes.io/inbound-cidrs: 10.0.0.0/8    # Restrict access

  # WAF (Web Application Firewall)
  alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:...

  # Tags
  alb.ingress.kubernetes.io/tags: Environment=prod,Team=backend
```

---

## Minikube vs EKS Ingress - Comparison

| Feature | Minikube (nginx) | EKS (ALB) |
|---------|-----------------|-----------|
| **Controller** | nginx Ingress Controller | AWS Load Balancer Controller |
| **ingressClassName** | `nginx` | `alb` |
| **Creates** | Nothing (internal routing) | Real AWS ALB |
| **Access URL** | minikube ip | ALB public DNS |
| **TLS** | Self-signed cert + K8s Secret | ACM certificate (free, auto-renew) |
| **Cost** | Free | ~$16/month per ALB + traffic |
| **Annotations prefix** | `nginx.ingress.kubernetes.io/` | `alb.ingress.kubernetes.io/` |
| **Target routing** | Always through kube-proxy | Instance mode or IP mode (direct) |
| **DNS** | /etc/hosts hack | Route 53 (real DNS) |
| **Rewrite** | `rewrite-target` annotation | ALB listener rules |
| **WAF support** | No | Yes (WAFv2 integration) |

### What Stays the Same

```
The Ingress YAML structure is the SAME:
  - apiVersion: networking.k8s.io/v1
  - kind: Ingress
  - spec.rules with host and paths

Only the annotations and ingressClassName change!
Your routing logic (paths, hosts) works the same way.
```

---

## Complete Production Example

```yaml
# production-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: production-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-south-1:123456789:certificate/xxx
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/tags: Environment=production,Team=platform
spec:
  ingressClassName: alb
  rules:
  # Frontend
  - host: www.mycompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80

  # API
  - host: api.mycompany.com
    http:
      paths:
      - path: /v1
        pathType: Prefix
        backend:
          service:
            name: api-v1-service
            port:
              number: 80
      - path: /v2
        pathType: Prefix
        backend:
          service:
            name: api-v2-service
            port:
              number: 80
```

```
What this creates in AWS:

1. ALB (internet-facing)
   - Listener port 80  --> Redirect to 443
   - Listener port 443 --> Rules:
     - Host: www.mycompany.com, Path: /* --> Frontend Target Group
     - Host: api.mycompany.com, Path: /v1* --> API v1 Target Group
     - Host: api.mycompany.com, Path: /v2* --> API v2 Target Group

2. ACM certificate attached (valid HTTPS, green lock)
3. Health checks on /healthz for each target group
4. Tags for cost tracking
```

---

## Troubleshooting EKS Ingress

```bash
# 1. ALB not being created
kubectl describe ingress <name>
# Look for events like:
#   Warning  FailedBuildModel  Error building ALB...

# Check controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# 2. Common issues:
#   - Controller not installed (no ALB gets created)
#   - IAM permissions missing (controller can't create ALB)
#   - Subnets not tagged properly
#   - ingressClassName: alb missing

# 3. Check if subnets are tagged (REQUIRED for ALB auto-discovery)
#   Public subnets need: kubernetes.io/role/elb = 1
#   Private subnets need: kubernetes.io/role/internal-elb = 1

# 4. Check ALB target health
aws elbv2 describe-target-health --target-group-arn <arn>

# 5. Security group not allowing traffic
aws ec2 describe-security-groups --group-ids <sg-id>
```

---

## Key Takeaways

1. **EKS uses AWS Load Balancer Controller** (not nginx) to create real AWS ALBs
2. **ingressClassName: alb** (not nginx) -- this is the key difference in YAML
3. **ALB for HTTP/HTTPS** (Layer 7, via Ingress), **NLB for TCP/UDP** (Layer 4, via Service)
4. **ACM certificates are free** and auto-renew -- much better than self-signed certs
5. **IP target type** routes directly to pods (faster, required for Fargate)
6. **Instance target type** routes through NodePort (simpler, works everywhere)
7. **Annotations change** between nginx and ALB, but the Ingress structure stays the same
8. **Route 53** replaces /etc/hosts for real DNS in production
9. Always check **subnet tags** -- ALB needs them to discover where to deploy
10. **One ALB per Ingress** by default (use IngressGroup annotation to share ALBs)

---

## Clean Up All Resources

```bash
# Delete all Ingress resources first (this deletes ALBs)
kubectl delete ingress --all

# Then delete apps
kubectl delete deployment app1 app2 web-app fast-app
kubectl delete service app1-service app2-service web-service fast-service

# Verify no ALBs remain in AWS
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s`)].LoadBalancerName'
```

---

**Theory:** [Day 17 - Ingress](../day17-ingress/notes.md) | **Local Demo:** [Ingress Demo (Minikube)](notes.md)
