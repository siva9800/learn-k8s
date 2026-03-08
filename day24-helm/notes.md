# Day 24 - Helm

## The Problem - YAML Hell

Imagine deploying a real application to Kubernetes. You need:

```
┌── Your Application Needs ─────────────────────────┐
│                                                     │
│   deployment.yaml     (app containers)              │
│   service.yaml        (networking)                  │
│   configmap.yaml      (configuration)               │
│   secret.yaml         (passwords)                   │
│   ingress.yaml        (external access)             │
│   hpa.yaml            (auto-scaling)                │
│   pdb.yaml            (disruption budget)           │
│   serviceaccount.yaml (RBAC)                        │
│   networkpolicy.yaml  (firewall)                    │
│                                                     │
│   = 9+ YAML files for ONE application!              │
└─────────────────────────────────────────────────────┘
```

Now multiply that by 3 environments (dev, staging, prod) where each has slightly different values (replicas, image tags, resource limits). You end up with **27+ nearly identical YAML files** to maintain.

**Problems:**
1. Too many YAML files to manage manually
2. No versioning -- can't easily rollback a deployment
3. No templating -- duplicate YAML everywhere
4. No dependency management -- "install A before B"
5. Sharing configurations is painful

**Solution:** Helm -- the package manager for Kubernetes.

---

## What Is Helm?

Helm is like `apt` for Ubuntu, `brew` for macOS, or `npm` for Node.js -- but for Kubernetes.

```
┌──────────── Without Helm ──────────┐    ┌──────────── With Helm ─────────────┐
│                                     │    │                                     │
│  kubectl apply -f deployment.yaml   │    │  helm install my-app ./my-chart    │
│  kubectl apply -f service.yaml      │    │                                     │
│  kubectl apply -f configmap.yaml    │    │  (One command deploys everything!) │
│  kubectl apply -f secret.yaml       │    │                                     │
│  kubectl apply -f ingress.yaml      │    │  helm upgrade my-app ./my-chart    │
│  kubectl apply -f hpa.yaml          │    │  (One command updates everything!) │
│  ...                                │    │                                     │
│                                     │    │  helm rollback my-app 1            │
│  (Many commands, error-prone)       │    │  (One command rolls back!)         │
└─────────────────────────────────────┘    └─────────────────────────────────────┘
```

---

## Helm Core Concepts

```
┌──────────────────────────────────────────────────────────────┐
│                     Helm Concepts                             │
│                                                               │
│  ┌─────────┐    ┌──────────┐    ┌────────────┐              │
│  │  Chart  │    │ Release  │    │ Repository │              │
│  ├─────────┤    ├──────────┤    ├────────────┤              │
│  │ Package │    │ Running  │    │ Collection │              │
│  │ of K8s  │    │ instance │    │ of charts  │              │
│  │ YAML    │    │ of a     │    │ (like npm  │              │
│  │ templates│   │ chart    │    │  registry) │              │
│  └─────────┘    └──────────┘    └────────────┘              │
│                                                               │
│  Think of it as:                                              │
│  Chart    = Recipe (instructions + ingredients list)          │
│  Release  = A cooked meal (deployed instance)                 │
│  Repo     = Cookbook (collection of recipes)                   │
└──────────────────────────────────────────────────────────────┘
```

| Concept | Description | Analogy |
|---------|-------------|---------|
| **Chart** | A package containing all K8s YAML templates | A recipe |
| **Release** | A deployed instance of a chart | A cooked meal |
| **Repository** | A place to store and share charts | A cookbook |
| **Values** | Configuration that customizes a chart | Ingredient amounts |

---

## Installing Helm

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows (with Chocolatey)
choco install kubernetes-helm

# Verify installation
helm version
# version.BuildInfo{Version:"v3.14.0", ...}
```

---

## Helm Basics - Working with Existing Charts

### Adding Repositories

```bash
# Add the official Bitnami repo (tons of popular charts)
helm repo add bitnami https://charts.bitnami.com/bitnami

# Add the Prometheus community repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Update repos (like apt update)
helm repo update
# ...Successfully got an update from the "bitnami" chart repository
# ...Successfully got an update from the "prometheus-community" chart repository

# List repos
helm repo list
# NAME                    URL
# bitnami                 https://charts.bitnami.com/bitnami
# prometheus-community    https://prometheus-community.github.io/helm-charts
```

### Searching for Charts

```bash
# Search in your added repos
helm search repo nginx
# NAME                    CHART VERSION   APP VERSION   DESCRIPTION
# bitnami/nginx           15.4.0          1.25.3        NGINX is an open source HTTP web server...
# bitnami/nginx-ingress   9.9.0           0.28.0        NGINX Ingress Controller...

# Search on Artifact Hub (public registry)
helm search hub prometheus
```

### Installing a Chart

```bash
# Basic install
helm install my-nginx bitnami/nginx
#           ↑           ↑
#        release      chart
#        name         name

# Install in a specific namespace
helm install my-nginx bitnami/nginx -n web --create-namespace

# Install with custom values
helm install my-nginx bitnami/nginx --set replicaCount=3

# Install with a values file
helm install my-nginx bitnami/nginx -f my-values.yaml

# See what would be installed (dry run)
helm install my-nginx bitnami/nginx --dry-run
```

```bash
# Check the release
helm list
# NAME       NAMESPACE   REVISION   STATUS     CHART          APP VERSION
# my-nginx   default     1          deployed   nginx-15.4.0   1.25.3
```

### Upgrading a Release

```bash
# Change the number of replicas
helm upgrade my-nginx bitnami/nginx --set replicaCount=5

# Upgrade with a values file
helm upgrade my-nginx bitnami/nginx -f production-values.yaml

# Check revision history
helm history my-nginx
# REVISION   STATUS       CHART          DESCRIPTION
# 1          superseded   nginx-15.4.0   Install complete
# 2          deployed     nginx-15.4.0   Upgrade complete
```

### Rolling Back

```bash
# Rollback to revision 1
helm rollback my-nginx 1
# Rollback was a success! Happy Helming!

helm history my-nginx
# REVISION   STATUS       CHART          DESCRIPTION
# 1          superseded   nginx-15.4.0   Install complete
# 2          superseded   nginx-15.4.0   Upgrade complete
# 3          deployed     nginx-15.4.0   Rollback to 1
```

### Uninstalling a Release

```bash
helm uninstall my-nginx
# release "my-nginx" uninstalled
```

---

## Chart Structure - What's Inside?

```
my-chart/
├── Chart.yaml          # Metadata about the chart (name, version, description)
├── values.yaml         # Default configuration values
├── charts/             # Dependencies (sub-charts)
├── templates/          # The actual K8s YAML templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    # Template helper functions
│   ├── hpa.yaml
│   └── NOTES.txt       # Post-install instructions shown to user
└── .helmignore         # Files to ignore when packaging
```

---

## Creating Your Own Chart

### Step 1: Scaffold a New Chart

```bash
helm create my-webapp
# Creating my-webapp

# This generates the full structure:
ls my-webapp/
# Chart.yaml  charts/  templates/  values.yaml
```

### Step 2: Edit Chart.yaml

```yaml
# my-webapp/Chart.yaml
apiVersion: v2
name: my-webapp
description: A simple web application chart
type: application
version: 0.1.0          # Chart version (change when chart changes)
appVersion: "1.0.0"     # App version (change when your app changes)
```

### Step 3: Edit values.yaml (Default Configuration)

```yaml
# my-webapp/values.yaml
replicaCount: 2

image:
  repository: my-registry/my-webapp
  tag: "1.0.0"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  hostname: myapp.example.com

resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilization: 80
```

### Step 4: Create Templates with Go Templating

```yaml
# my-webapp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-webapp          # Uses the release name
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}       # From values.yaml
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: webapp
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: 80
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

```yaml
# my-webapp/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-svc
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: 80
  selector:
    app: {{ .Release.Name }}
```

### Step 5: Template Conditionals

```yaml
# my-webapp/templates/ingress.yaml
{{- if .Values.ingress.enabled }}            # Only create if ingress is enabled
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-ingress
spec:
  rules:
    - host: {{ .Values.ingress.hostname }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .Release.Name }}-svc
                port:
                  number: {{ .Values.service.port }}
{{- end }}
```

### Step 6: Install Your Chart

```bash
# Install with defaults
helm install my-release ./my-webapp

# Install with overrides for production
helm install my-release ./my-webapp \
  --set replicaCount=5 \
  --set image.tag="2.0.0" \
  --set ingress.enabled=true

# Or use a separate values file for each environment
helm install my-release ./my-webapp -f values-production.yaml
```

---

## Helm Templating Quick Reference

```
┌────────────────────── Helm Template Syntax ───────────────────────┐
│                                                                    │
│  {{ .Values.key }}          Access values.yaml                     │
│  {{ .Release.Name }}        Release name (helm install NAME)       │
│  {{ .Release.Namespace }}   Namespace it's installed in            │
│  {{ .Chart.Name }}          Chart name from Chart.yaml             │
│  {{ .Chart.Version }}       Chart version from Chart.yaml          │
│                                                                    │
│  {{- if .Values.ingress.enabled }}                                 │
│    ... create ingress ...                                          │
│  {{- end }}                                                        │
│                                                                    │
│  {{- range .Values.hosts }}                                        │
│    - host: {{ . }}           Loop over a list                      │
│  {{- end }}                                                        │
│                                                                    │
│  {{ .Values.x | default "fallback" }}   Default value              │
│  {{ .Values.x | quote }}                Wrap in quotes             │
│  {{ toYaml .Values.x | nindent 4 }}    Convert to YAML            │
└────────────────────────────────────────────────────────────────────┘
```

---

## Useful Helm Commands

```bash
# Validate your chart
helm lint ./my-webapp
# ==> Linting ./my-webapp
# [INFO] Chart.yaml: icon is recommended
# 1 chart(s) linted, 0 chart(s) failed

# See rendered templates (without installing)
helm template my-release ./my-webapp

# Dry run an install
helm install my-release ./my-webapp --dry-run --debug

# Get the values of a deployed release
helm get values my-release

# Get all info about a release
helm get all my-release

# Package chart for sharing
helm package ./my-webapp
# Successfully packaged chart and saved it to: my-webapp-0.1.0.tgz
```

---

## Popular Helm Charts

These are charts you will use in almost every production cluster:

```
┌──────────────────────────────────────────────────────────────┐
│                    Popular Helm Charts                         │
├─────────────────────┬────────────────────────────────────────┤
│ Chart               │ Purpose                                │
├─────────────────────┼────────────────────────────────────────┤
│ ingress-nginx       │ NGINX Ingress Controller               │
│ cert-manager        │ Automatic TLS certificates (Let's      │
│                     │ Encrypt)                                │
│ prometheus          │ Monitoring & alerting                   │
│ grafana             │ Dashboards & visualization              │
│ argocd              │ GitOps continuous delivery              │
│ external-dns        │ Automatic DNS record management         │
│ sealed-secrets      │ Encrypted secrets in Git                │
│ metrics-server      │ Resource metrics for HPA                │
│ loki-stack          │ Log aggregation                         │
│ redis               │ In-memory cache                         │
│ postgresql           │ PostgreSQL database                     │
└─────────────────────┴────────────────────────────────────────┘
```

```bash
# Example: Install the NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# Example: Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

---

## Key Takeaways

```
┌─────────────────────────────────────────────────────────────┐
│                      Helm TL;DR                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Helm = Package manager for Kubernetes                    │
│                                                              │
│  2. Chart = Package of templated K8s YAML files              │
│                                                              │
│  3. Release = A deployed instance of a chart                 │
│                                                              │
│  4. values.yaml = Configuration that customizes a chart      │
│                                                              │
│  5. Core commands:                                           │
│     helm install   - Deploy a chart                          │
│     helm upgrade   - Update a release                        │
│     helm rollback  - Revert to a previous revision           │
│     helm uninstall - Remove a release                        │
│                                                              │
│  6. Go templating: {{ .Values.key }} accesses values.yaml    │
│                                                              │
│  7. Use --dry-run and helm template to preview changes       │
│                                                              │
│  8. Use helm lint to validate your charts                    │
│                                                              │
│  9. Popular charts: ingress-nginx, cert-manager, prometheus  │
│                                                              │
│ 10. One chart + different values files = multiple envs       │
└─────────────────────────────────────────────────────────────┘
```

---

> **Hands-On Demo:** [Helm Demo - Build, Deploy, Upgrade, Rollback](demo.md)

**Previous:** [<-- Day 23 - Network Policies](../day23-network-policies/notes.md) | **Next:** [Day 25 - Monitoring & Logging -->](../day25-monitoring-logging/notes.md)
