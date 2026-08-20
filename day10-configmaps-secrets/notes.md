# Day 10 - ConfigMaps & Secrets

> **Goal:** Keep configuration and sensitive data **out of your container images** by injecting them at runtime with ConfigMaps and Secrets.

## Learning Objectives
- Explain why config should be separate from code
- Create ConfigMaps and Secrets (imperatively and with YAML)
- Inject them as **environment variables** or **mounted files (volumes)**
- Understand the critical truth: **Secrets are base64-ENCODED, NOT encrypted by default**

---

## Real-World Analogy: The Recipe vs. The Ingredients

Think of your container image as a **recipe card** - it lists the *steps* but should never hard-code the *specific ingredients* for one kitchen.

- A **ConfigMap** is like a **shopping list taped to the fridge**: "use 2% milk, oven at 180°C." Non-secret settings anyone can read.
- A **Secret** is like the **safe combination or your card PIN**: still just written on paper, but you keep it locked away and don't read it aloud.

You hand the cook (the Pod) the shopping list and the PIN **at cooking time** - you don't reprint the recipe card every time a price or PIN changes.

> Same image, different config per environment (dev / staging / prod). Change the ConfigMap, not the image.

---

## How Config Reaches a Pod

```mermaid
flowchart LR
    CM[ConfigMap<br/>non-secret settings] -->|env var| Pod
    CM -->|mounted file| Pod
    SEC[Secret<br/>sensitive data] -->|env var| Pod
    SEC -->|mounted file| Pod
    subgraph Pod[Pod / Container]
        ENV[Environment variables<br/>e.g. APP_COLOR]
        VOL[Volume files<br/>e.g. /etc/config/...]
    end
```

There are **two ways** to inject either one: as **environment variables** (simple key/value) or as **mounted files** (whole config files / certs).

---

## The Problem - Hardcoded Configuration

Look at this container:

```yaml
containers:
- name: myapp
  image: myapp:1.0
  env:
    - name: DB_HOST
      value: "192.168.1.100"      # ← Hardcoded!
    - name: DB_PASSWORD
      value: "supersecret123"      # ← Password in YAML! 
```

**Problems:**
1. To change the DB host, you have to **rebuild and redeploy** the container
2. Password is visible to anyone who reads the YAML file
3. Different values for dev/staging/prod require different YAML files

**Solution:**
- **ConfigMap** = Store non-sensitive configuration separately
- **Secret** = Store sensitive data (passwords, tokens) separately

---

## ConfigMaps

### What Is a ConfigMap?

A ConfigMap stores **key-value pairs** of configuration data. Your pods read from it instead of hardcoding values.

```
┌── ConfigMap ──┐          ┌── Pod ──┐
│ DB_HOST=...   │ ────────→│  reads  │
│ APP_MODE=prod │          │  config │
│ LOG_LEVEL=info│          │  from   │
└───────────────┘          │  here   │
                           └─────────┘
```

### Creating a ConfigMap

#### Method 1: From Command Line

```bash
# From literal values
kubectl create configmap app-config \
  --from-literal=DB_HOST=192.168.1.100 \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=info

# From a file
kubectl create configmap nginx-config --from-file=nginx.conf

# From env file
kubectl create configmap app-config --from-env-file=config.env
```

#### Method 2: YAML (Recommended)

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  DB_HOST: "192.168.1.100"
  APP_MODE: "production"
  LOG_LEVEL: "info"

  # You can also store entire files
  app.properties: |
    server.port=8080
    spring.datasource.url=jdbc:mysql://db:3306/mydb
```

```bash
kubectl apply -f configmap.yaml
```

### Using ConfigMap in a Pod

#### Option 1: As Environment Variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: nginx

    # Load specific keys
    env:
    - name: DATABASE_HOST
      valueFrom:
        configMapKeyRef:
          name: app-config       # ConfigMap name
          key: DB_HOST           # Key in ConfigMap

    # Or load ALL keys as env vars
    envFrom:
    - configMapRef:
        name: app-config
```

#### Option 2: As a Volume (File Mount)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: nginx
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config      # Where to mount
  volumes:
  - name: config-volume
    configMap:
      name: app-config           # Each key becomes a file
```

This creates files like:
```
/etc/config/DB_HOST           → contains "192.168.1.100"
/etc/config/APP_MODE          → contains "production"
/etc/config/app.properties    → contains the full file content
```

---

## Secrets

### The Most Important Point About Secrets

> **A Kubernetes Secret is base64-ENCODED, not ENCRYPTED.**
>
> Base64 is just a reversible text format - **anyone who can read the Secret can decode it instantly.** It is NOT security on its own.

```bash
# "Encoding" is trivially reversible - no password needed:
echo -n 'S3cr3t!' | base64        # -> UzNjcjN0IQ==
echo 'UzNjcjN0IQ==' | base64 -d   # -> S3cr3t!   (decoded right back)
```

### But WHY base64 at all? (the real reason)

If base64 gives **zero** security, why does Kubernetes bother encoding at all? The answer has **nothing to do with secrecy** - it's about **safely carrying *any* bytes through text-only systems.**

> **Analogy: shipping a fragile item by postcard.**
> A postcard (YAML/JSON) can only carry **plain printable text**. But a secret might be a TLS private key, a `.p12` certificate, or a password containing newlines, tabs, null bytes, or emoji. You can't write raw binary on a postcard - it gets mangled. So you **translate the bytes into a safe alphabet** (A-Z, a-z, 0-9, `+`, `/`) that survives any postcard, any language, any mail system. That translation is base64. The postcard is still readable by anyone - it was never about hiding.

Concretely, base64 exists in Secrets because:

1. **Secrets can hold arbitrary binary data**, not just strings - certificates, keystores, SSH keys, `.pfx` files. Raw binary bytes are **not valid inside YAML or JSON** (they can contain control characters, null bytes, or byte sequences that aren't valid UTF-8).
2. **The whole Kubernetes pipeline is text/JSON.** Your YAML → `kubectl` → the API server → **etcd** all move data as JSON. base64 guarantees every byte survives that journey **unchanged** - no encoding corruption, no "it worked on my machine."
3. **It's a transport/serialization format, not a security control** - exactly like base64 in email attachments or `data:` URLs. The `data:` field is base64; the convenience field `stringData:` just base64-encodes *for* you at apply time.

```mermaid
flowchart LR
    A["Raw secret bytes<br/>(may be binary:<br/>TLS key, .p12, ...)"] -->|base64 encode| B["Safe text<br/>(A-Z a-z 0-9 + /)"]
    B -->|"stored in"| C["YAML / JSON"]
    C --> D["API server"]
    D --> E[("etcd")]
    E -->|base64 decode| F["Container sees<br/>ORIGINAL bytes<br/>as env var / file"]
    style A fill:#3a1a1a,stroke:#e06c75,color:#fff
    style F fill:#0d2818,stroke:#3fb950,color:#fff
```

**Takeaway:** base64 answers *"how do I safely store these bytes?"* - **not** *"how do I keep them secret?"* Secrecy is a **separate** job handled by encryption-at-rest + RBAC + external managers (below).

To make Secrets **actually** secure, you must additionally:
- Enable **encryption at rest** (etcd encryption) on the cluster, and/or
- Use an external secrets manager (HashiCorp Vault, AWS/GCP/Azure secret stores), and
- Restrict access with **RBAC**.

So why use Secrets at all? They keep sensitive values out of your image, can be mounted as in-memory (tmpfs) files instead of on disk, and integrate with RBAC so you can limit who reads them.

### What Is a Secret?

A Secret is like a ConfigMap, but for **sensitive data**. Values are base64 encoded (not encrypted by default!).

```
┌── Secret ─────┐          ┌── Pod ──┐
│ DB_PASS=***   │ ────────→│  reads  │
│ API_KEY=***   │          │ secrets │
│ TLS_CERT=***  │          │  from   │
└───────────────┘          │  here   │
                           └─────────┘
```

### Creating a Secret

#### Method 1: Command Line

```bash
kubectl create secret generic db-secret \
  --from-literal=DB_PASSWORD=supersecret123 \
  --from-literal=DB_USERNAME=admin
```

#### Method 2: YAML

**Important:** Values must be **base64 encoded** in YAML:

```bash
# Encode your values first
echo -n 'supersecret123' | base64
# Output: c3VwZXJzZWNyZXQxMjM=

echo -n 'admin' | base64
# Output: YWRtaW4=
```

```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  DB_PASSWORD: c3VwZXJzZWNyZXQxMjM=    # base64 encoded
  DB_USERNAME: YWRtaW4=                  # base64 encoded
```

Or use `stringData` to avoid manual base64 encoding:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:                              # ← stringData (not data)
  DB_PASSWORD: "supersecret123"          # plain text, K8s encodes it
  DB_USERNAME: "admin"
```

### Using Secrets in a Pod

#### As Environment Variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: nginx
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: DB_PASSWORD

    # Or load all keys
    envFrom:
    - secretRef:
        name: db-secret
```

#### As Volume (File Mount)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: nginx
    volumeMounts:
    - name: secret-volume
      mountPath: /etc/secrets
      readOnly: true
  volumes:
  - name: secret-volume
    secret:
      secretName: db-secret
```

---

## Secrets + RBAC — What "Stricter Access Control" Actually Means

The table below says a Secret "can have stricter access controls" than a ConfigMap. That single line hides an important idea, so let's unpack it properly.

### RBAC in one picture

**RBAC = Role-Based Access Control.** It answers one question: **"WHO is allowed to do WHAT to WHICH resources?"**

> **Analogy: a hotel keycard system.**
> Every keycard (a **ServiceAccount** or user) opens only the doors it's been programmed for. A cleaner's card opens guest rooms but **not** the safe room or the cash office. In Kubernetes, a Pod runs as a **ServiceAccount** (its keycard), and a **Role** is the list of doors that card opens. "Stricter access control on Secrets" means: *program the cards so almost nobody's card opens the Secrets room.*

RBAC has three pieces:

```mermaid
flowchart LR
    SA["Subject<br/>(ServiceAccount / user)<br/>= the keycard"] -->|RoleBinding<br/>'link card to permissions'| R["Role<br/>= list of allowed doors<br/>(verbs on resources)"]
    R -->|grants access to| RES["Resources<br/>secrets, configmaps, pods..."]
    style SA fill:#0a1a3a,stroke:#5b8def,color:#fff
    style R fill:#2a1a3a,stroke:#b48ead,color:#fff
    style RES fill:#0d2818,stroke:#3fb950,color:#fff
```

- **Role** (or **ClusterRole**) — a list of *allowed actions*: which **verbs** (`get`, `list`, `watch`, `create`, `update`, `delete`) on which **resources** (`secrets`, `configmaps`, `pods`…).
- **RoleBinding** (or **ClusterRoleBinding**) — glues a Role to a **subject** (a ServiceAccount, user, or group).
- **ServiceAccount** — the identity a Pod runs as. If you don't set one, Pods use the namespace's `default` ServiceAccount.

### Why Secrets deserve *their own, tighter* rules

Here's the key insight: **`secrets` is a distinct resource type in RBAC, separate from `configmaps`.** That means you can grant someone full access to ConfigMaps while giving them **zero** access to Secrets - even in the same namespace. This is the whole point of "stricter access control."

A common real-world mistake is being too generous:

```yaml
# ❌ TOO BROAD — this Role can read EVERY Secret in the namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: team-a
  name: reads-everything
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]     # can dump ALL secrets
```

Anyone bound to that Role can run `kubectl get secrets -o yaml` and walk away with every password in the namespace. Least-privilege says: **scope it down to the exact Secret needed.**

```yaml
# ✅ LEAST PRIVILEGE — can read ONLY the one Secret it needs, nothing else
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: team-a
  name: read-db-secret-only
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["db-secret"]        # ← locked to a single named Secret
  verbs: ["get"]                      # ← read one, can't 'list' them all
```

```yaml
# Bind that narrow Role to a specific ServiceAccount (the app's "keycard")
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: team-a
  name: app-reads-db-secret
subjects:
- kind: ServiceAccount
  name: myapp-sa
  namespace: team-a
roleRef:
  kind: Role
  name: read-db-secret-only
  apiGroup: rbac.authorization.k8s.io
```

> ⚠️ **Subtle but important:** `get` with `resourceNames` lets you fetch a Secret *if you already know its name*, but **not** `list` them. Granting `list`/`watch` on `secrets` effectively exposes **all** of them - so hand those verbs out very sparingly.

### Practical RBAC rules of thumb for Secrets

1. **Separate the verbs.** Reserve `list`/`watch` on `secrets` for a tiny set of trusted controllers. Most apps only need `get` on one named Secret - and usually not even that (they get it via an env var / volume mount, which the **kubelet** reads on their behalf, so the Pod itself needs no `get` permission at all).
2. **One ServiceAccount per app.** Don't let everything share the `default` SA. A dedicated SA = a keycard you can scope precisely and revoke independently.
3. **Namespaces are your first fence.** A `Role`/`RoleBinding` is namespace-scoped, so put sensitive workloads in their own namespace and keep cross-namespace access out with `ClusterRole` only where truly needed.
4. **Audit who can read secrets.** Test any identity with:
   ```bash
   # Can this ServiceAccount read secrets in this namespace?
   kubectl auth can-i get secrets --as=system:serviceaccount:team-a:myapp-sa -n team-a
   kubectl auth can-i list secrets --as=system:serviceaccount:team-a:myapp-sa -n team-a
   ```
5. **Remember: cluster-admins can still read everything.** RBAC limits *most* users, but a cluster-admin (and anyone who can read etcd) can see decoded Secrets. That's exactly why encryption-at-rest and **external secret managers** exist - see the companion file below.

> 📎 There's a whole day on this later: **[Day 17 - RBAC & Cluster Security](../day17-rbac-security/notes.md)**. Here we only cover *how RBAC applies to Secrets specifically*.

---

## 🏭 Going to Production: External Secrets & Real-World Patterns

Everything above is enough for a demo cluster. **Real production** almost never stores raw Secrets in Git or relies on base64 alone. Instead teams use **encryption-at-rest**, an **external secrets manager** (AWS Secrets Manager, Vault, Azure Key Vault…), and tools that **sync** those into Kubernetes automatically.

Because that's a big topic on its own, it lives in a dedicated companion file:

> ### 👉 **[Production-Grade Secrets & Config Management →](production-secrets.md)**
> Covers: encryption-at-rest (etcd + KMS) · **External Secrets Operator (ESO)** · **Secrets Store CSI Driver** · **Sealed Secrets** · **SOPS** · **HashiCorp Vault** · GitOps-safe patterns · a decision guide for choosing between them.

---

## ConfigMap vs Secret

| Feature | ConfigMap | Secret |
|---------|-----------|--------|
| **Purpose** | Non-sensitive config | Sensitive data |
| **Stored as** | Plain text | Base64 encoded |
| **Size limit** | 1 MB | 1 MB |
| **Example data** | DB host, log level, feature flags | Passwords, API keys, TLS certs |
| **RBAC** | Standard | Can have stricter access controls ([see above](#secrets--rbac--what-stricter-access-control-actually-means)) |

**Important:** Base64 is NOT encryption! Anyone can decode it. For real security, use:
- Kubernetes RBAC (restrict who can read secrets) — [explained above](#secrets--rbac--what-stricter-access-control-actually-means)
- Encrypted etcd (encrypt secrets at rest) — [companion file](production-secrets.md)
- External secret managers (AWS Secrets Manager, HashiCorp Vault) — [companion file](production-secrets.md)

---

## Useful Commands

```bash
# ConfigMaps
kubectl get configmaps              # or: kubectl get cm
kubectl describe configmap app-config
kubectl delete configmap app-config

# Secrets
kubectl get secrets
kubectl describe secret db-secret   # values are hidden
kubectl get secret db-secret -o yaml  # see base64 values

# Decode a secret value
kubectl get secret db-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode
```

---

## Hands-On Lab

```bash
# 1. Create a ConfigMap
kubectl create configmap app-config \
  --from-literal=APP_COLOR=blue \
  --from-literal=APP_MODE=production

# 2. Create a Secret
kubectl create secret generic app-secret \
  --from-literal=API_KEY=my-secret-key-123

# 3. Create a pod that uses both
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: config-test
spec:
  containers:
  - name: busybox
    image: busybox
    command: ["sh", "-c", "echo Color=\$APP_COLOR Mode=\$APP_MODE Key=\$API_KEY && sleep 3600"]
    envFrom:
    - configMapRef:
        name: app-config
    - secretRef:
        name: app-secret
EOF

# 4. Check the values
kubectl logs config-test
# Output: Color=blue Mode=production Key=my-secret-key-123
```

---

## Common Mistakes

1. **Believing Secrets are encrypted.** They are **base64-encoded only** by default - anyone with read access decodes them in one command. Add etcd encryption-at-rest + RBAC for real protection.
2. **Committing Secret YAML with real values to Git.** Base64 hides nothing. Never push real credentials to a repo.
3. **Hand-encoding into `data:` and getting it wrong** (e.g. a trailing newline). Use `echo -n` to avoid the newline, or just use `stringData:`.
4. **Expecting env-var changes to reach a running Pod.** Editing a ConfigMap/Secret used as **env vars** does NOT update existing Pods - you must `kubectl rollout restart`. (Mounted-volume values do update eventually.)
5. **Key name mismatch.** The `key:` in `configMapKeyRef`/`secretKeyRef` must exactly match a key in the ConfigMap/Secret, or the Pod fails to start.

---

## Quick Self-Check

1. Why should configuration live outside the container image?
2. What are the two ways to inject a ConfigMap or Secret into a Pod?
3. **True or false:** Kubernetes Secrets are encrypted by default. Explain your answer.
4. What does `stringData:` do that `data:` doesn't?
5. You changed a ConfigMap used as env vars, but the running Pod still shows the old value. Why, and how do you fix it?
6. If base64 gives no security, **why does Kubernetes encode Secrets in base64 at all?**
7. Why is granting `list` on `secrets` far more dangerous than granting `get` with a `resourceNames` restriction?
8. Name two production tools/patterns that keep the *real* secret out of Git and out of etcd, and one sentence on how each works. (See the [companion file](production-secrets.md).)

---

## Summary

**ConfigMaps** hold non-secret settings; **Secrets** hold sensitive data - but Secrets are only **base64-encoded, not encrypted**, so add etcd encryption-at-rest and RBAC for real security. Inject either as **environment variables** or **mounted files**, keeping the same image reusable across dev, staging, and prod.

Next up → [Day 11 - Amazon EKS](../day11-eks/notes.md)

---

## Key Takeaways

1. **Never hardcode** configuration or passwords in your YAML or Docker images
2. **ConfigMap** = non-sensitive configuration (DB host, feature flags, config files)
3. **Secret** = sensitive data (passwords, API keys, TLS certificates)
4. Both can be used as **environment variables** or **volume mounts**
5. **Base64 is not encryption** - it's a *transport format* for arbitrary/binary bytes. Use proper secret management in production
6. **`stringData`** in Secrets lets you write plain text (K8s encodes it for you)
7. **RBAC on `secrets` is separate from `configmaps`** - scope reads to a single named Secret (`resourceNames`), and guard `list`/`watch` closely
8. **In production, don't store raw Secrets** - use encryption-at-rest + an external manager → [production-secrets.md](production-secrets.md)

---

## Practice / Homework

1. Create a ConfigMap with 3 key-value pairs
2. Create a Secret with a username and password
3. Create a Pod that reads from both ConfigMap and Secret
4. Verify values using `kubectl exec <pod> -- env`
5. Try mounting ConfigMap as a volume and read the files
6. Decode a secret: `kubectl get secret <name> -o jsonpath='{.data.KEY}' | base64 --decode`

---

**Previous:** [← Day 09 - Namespaces](../day09-namespaces/notes.md)
**Next:** [Day 11 - Amazon EKS →](../day11-eks/notes.md)
