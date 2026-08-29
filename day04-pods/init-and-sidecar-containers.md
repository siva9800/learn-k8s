# Day 04 (Deep Dive) - Init Containers and Sidecar Containers

> **Companion to [Day 04 - Kubernetes Pods](notes.md).** A Pod can hold **more than one container**. This page covers the two patterns that use that: **init containers** (setup that must finish *before* your app starts) and **sidecar containers** (helpers that run *alongside* your app).

> **Why this matters:** these are the building blocks behind service meshes, log shippers, secret injectors, and "wait for the database" startup logic. You will see them in almost every production Pod, so knowing how they start, stop, and share resources is essential.

---

## A Pod Is Not Always One Container

A Pod is a group of containers that share a network (same IP/localhost) and can share volumes. Containers in a Pod come in three roles:

| Role | When it runs | Purpose |
|------|--------------|---------|
| **init container** | Before app containers, **in order, to completion** | One-time setup (wait for a dependency, migrate a DB, fix permissions) |
| **app container** | The main workload | Your actual application |
| **sidecar container** | **Alongside** the app for the pod's whole life | Ongoing helper (proxy, log shipper, secrets agent) |

```mermaid
flowchart LR
    I1["init-1<br/>(runs, exits 0)"] --> I2["init-2<br/>(runs, exits 0)"]
    I2 --> SC["sidecar starts<br/>(stays running)"]
    SC --> APP["app container starts"]
    APP -. "both run together" .- SC
```

---

## Init Containers

An **init container** runs **before** the app containers, **one at a time, in order**, and each must **exit 0** before the next starts. Only when all init containers succeed do the app containers start.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  initContainers:
  - name: wait-for-db                     # (1) runs first
    image: busybox:1.36
    command: ['sh', '-c', 'until nc -z db 5432; do echo waiting for db; sleep 2; done']
  - name: run-migrations                  # (2) runs after (1) succeeds
    image: myapp-migrate:1.4
    command: ['./migrate.sh']
  containers:
  - name: web                             # (3) starts only after all init containers pass
    image: myapp:1.4
    ports:
    - containerPort: 8080
```

**What init containers are for:**
- **Wait for a dependency** to be reachable (a database, a service, a config server).
- **Run schema migrations** or seed data before the app boots.
- **Fetch or render config/secrets** into a shared volume the app then reads.
- **Fix volume permissions** (chown/chmod a mounted volume before the app uses it).
- **Clone a git repo** or download assets into a shared `emptyDir`.

**Key behaviours:**
- They **share volumes** with the app containers, so init output is available to the app.
- If an init container **fails**, the kubelet **retries** it (per the pod's `restartPolicy`); the pod shows `Init:Error` or `Init:CrashLoopBackOff` and the app never starts.
- A pod mid-init shows status like `Init:1/2` (on init container 2 of 2).
- **Resource note:** the pod's effective request/limit is the **larger** of (the sum across app containers) and (the largest single init container) - because init containers run one at a time and before the app.

```bash
kubectl get pod web
# NAME   READY   STATUS     RESTARTS   AGE
# web    0/1     Init:0/2   0          8s      <- still running init container 1

kubectl logs web -c wait-for-db          # -c selects a specific (init) container
```

---

## Sidecar Containers

A **sidecar** is a helper container that runs **for the whole life of the pod, alongside** the app. Because it shares the pod's network and volumes, it can proxy the app's traffic, tail its logs, or refresh its secrets.

**Common sidecars:** a service-mesh proxy (Envoy/Istio), a log shipper (Fluent Bit), a config reloader, a secrets agent (Vault agent), or a metrics exporter.

### The old problem, and native sidecars

Historically a sidecar was "just another entry in `containers:`" - which caused two headaches:

1. **Startup ordering was not guaranteed** - the app might start before its proxy was ready.
2. **In Jobs, a never-exiting sidecar blocked completion** - the Job waits for all containers to finish, but the log shipper never exits, so the Job hangs forever.

**Native sidecar containers** (stable from Kubernetes 1.29) fix this. A native sidecar is written as an **init container with `restartPolicy: Always`**. It starts during the init sequence but **keeps running** alongside the app, and is **shut down after** the app containers on termination.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      initContainers:
      - name: log-shipper                 # a NATIVE SIDECAR
        image: fluent-bit:3.0
        restartPolicy: Always             # <-- this makes it a sidecar (starts, then STAYS)
        volumeMounts:
        - { name: logs, mountPath: /var/log/app }
      containers:
      - name: web
        image: myapp:1.4
        volumeMounts:
        - { name: logs, mountPath: /var/log/app }
      volumes:
      - name: logs
        emptyDir: {}
```

**Why native sidecars are better:**
- They **start before** the app (ordering solved) and are **guaranteed running** when the app starts.
- They **do not block Job completion** - the pod finishes when the app containers exit.
- They are **terminated last**, so the app can flush logs/close connections while the sidecar is still up.

---

## Init vs Sidecar - the difference

| | Init container | Sidecar (native) |
|---|----------------|------------------|
| **Lifetime** | Runs once, **exits** before app | Runs the **whole pod life** |
| **Ordering** | Strictly before app, in sequence | Starts before app, keeps running |
| **Defined under** | `initContainers` | `initContainers` **with `restartPolicy: Always`** |
| **Purpose** | One-time setup | Continuous helper |
| **Blocks Job completion?** | No (it exits) | No (native sidecars are exempt) |

> **The one-liner:** an **init container does a job and leaves**; a **sidecar comes to work and stays** for the whole shift.

---

## Common Mistakes

1. **Plain sidecar in a Job that never completes.** A classic `containers:` sidecar that never exits makes the Job hang. Use a **native sidecar** (`initContainers` + `restartPolicy: Always`).
2. **Heavy work in an init container.** Init runs before the app, so a slow init delays every start and every restart. Keep it lean, or move ongoing work to a sidecar.
3. **Assuming startup order for plain sidecars.** Without native sidecars, the app can start before the helper is ready. Prefer native sidecars when ordering matters.
4. **Forgetting `-c` when reading logs.** `kubectl logs pod` picks the default container; use `kubectl logs pod -c <name>` for init/sidecar containers.
5. **Not sharing a volume.** Init output only reaches the app if both mount the **same** volume (often an `emptyDir`).

---

## Quick Self-Check

1. In what order do two init containers and the app container start?
2. Your app must not start until the database is reachable. Which pattern, and how?
3. Why did log-shipper sidecars historically break **Jobs**, and what fixes it?
4. What single field turns an init container into a native sidecar?
5. Where does init-container output need to live so the app container can use it?

<details>
<summary>Answers</summary>

1. init-1 runs to completion, then init-2 runs to completion, then the app container starts. Init containers are sequential; the app waits for all of them.
2. An **init container** that loops until the DB port is reachable (e.g. `until nc -z db 5432; do sleep 2; done`); the app container only starts once it exits 0.
3. A plain sidecar never exits, so the Job (which waits for all containers to finish) hangs forever. **Native sidecars** (init container with `restartPolicy: Always`) are exempt from blocking Job completion.
4. `restartPolicy: Always` on an entry under `initContainers`.
5. In a **shared volume** (commonly an `emptyDir`) mounted by both the init container and the app container.

</details>

---

## Summary

- A Pod can run **init containers** (ordered, run-to-completion setup) and **app/sidecar containers**.
- **Init containers** wait for dependencies, migrate databases, fix permissions, or fetch config - each must exit 0 before the next, and before the app starts.
- **Native sidecars** (init container with `restartPolicy: Always`) run alongside the app for the pod's whole life, start first, terminate last, and do not block Job completion - the modern way to run proxies, log shippers, and secret agents.

---

**Back to:** [Day 04 - Kubernetes Pods](notes.md)
