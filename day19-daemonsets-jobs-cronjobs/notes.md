# Day 19 - DaemonSets, Jobs & CronJobs

## The Big Picture

So far, we've used **Deployments** to run our applications. Deployments are great for stateless apps where you decide how many replicas you want. But what about these scenarios?

1. You need a **log collector running on every single node** in the cluster
2. You need to run a **one-time database migration** that finishes and stops
3. You need to **generate a report every night at 2 AM**

Deployments can't handle these well. That's where **DaemonSets**, **Jobs**, and **CronJobs** come in.

```
┌─────────────────────────────────────────────────────────────────┐
│                  Kubernetes Workload Types                      │
│                                                                 │
│  Deployment    = "Run N replicas, keep them running forever"    │
│  DaemonSet     = "Run one pod on EVERY node, automatically"    │
│  Job           = "Run a task once, then stop"                   │
│  CronJob       = "Run a task on a schedule (like cron)"        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 1: DaemonSets

### What Is a DaemonSet?

A DaemonSet ensures that **one copy of a pod runs on every node** in the cluster. When a new node is added, the DaemonSet automatically places a pod on it. When a node is removed, the pod is garbage collected.

```
┌──────────────── Kubernetes Cluster ─────────────────┐
│                                                      │
│  Node 1              Node 2              Node 3      │
│  ┌──────────┐       ┌──────────┐       ┌──────────┐ │
│  │ DS Pod   │       │ DS Pod   │       │ DS Pod   │ │
│  │ (fluentd)│       │ (fluentd)│       │ (fluentd)│ │
│  │          │       │          │       │          │ │
│  │ App Pods │       │ App Pods │       │ App Pods │ │
│  │ ...      │       │ ...      │       │ ...      │ │
│  └──────────┘       └──────────┘       └──────────┘ │
│                                                      │
│  New Node 4 added? --> DaemonSet AUTOMATICALLY       │
│                        places a pod on it!           │
└──────────────────────────────────────────────────────┘
```

### Why Not Just Use a Deployment?

| Feature | Deployment | DaemonSet |
|---------|-----------|-----------|
| Number of pods | You choose (replicas: N) | Exactly 1 per node (automatic) |
| New node added | Nothing happens | Pod auto-scheduled |
| Node removed | Nothing happens | Pod auto-removed |
| Use case | Application workloads | Node-level infrastructure |

### Common Use Cases for DaemonSets

1. **Log collectors** - Fluentd, Filebeat (collect logs from every node)
2. **Monitoring agents** - Prometheus Node Exporter, Datadog agent
3. **Network plugins** - kube-proxy, Calico, Cilium (CNI plugins)
4. **Storage daemons** - GlusterFS, Ceph agents
5. **Security agents** - Falco, antivirus scanners

Think of it this way: if every node needs it, it's a DaemonSet.

### DaemonSet YAML Example

```yaml
# daemonset-fluentd.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: kube-system
  labels:
    app: fluentd
spec:
  selector:
    matchLabels:
      app: fluentd               # Must match template labels
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      containers:
      - name: fluentd
        image: fluentd:v1.16
        resources:
          limits:
            memory: "200Mi"
            cpu: "100m"
          requests:
            memory: "100Mi"
            cpu: "50m"
        volumeMounts:
        - name: varlog
          mountPath: /var/log     # Mount node's log directory
      volumes:
      - name: varlog
        hostPath:
          path: /var/log          # Access logs from the host node
```

> Notice: No `replicas` field! DaemonSets don't need it -- they automatically run one pod per node.

### Working with DaemonSets

```bash
# Create the DaemonSet
kubectl apply -f daemonset-fluentd.yaml

# List DaemonSets
kubectl get daemonsets -n kube-system
# NAME       DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
# fluentd    3         3         3       3            3           <none>          30s

# DESIRED = number of nodes, CURRENT = pods created, READY = pods running

# See which pods are on which nodes
kubectl get pods -n kube-system -o wide -l app=fluentd
# NAME            READY   STATUS    NODE
# fluentd-abc12   1/1     Running   node-1
# fluentd-def34   1/1     Running   node-2
# fluentd-ghi56   1/1     Running   node-3

# Describe a DaemonSet
kubectl describe daemonset fluentd -n kube-system

# Delete a DaemonSet
kubectl delete daemonset fluentd -n kube-system
```

### Running DaemonSet on Specific Nodes Only

You can use `nodeSelector` or `affinity` to limit which nodes get the DaemonSet pod:

```yaml
# daemonset-gpu-monitor.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: gpu-monitor
spec:
  selector:
    matchLabels:
      app: gpu-monitor
  template:
    metadata:
      labels:
        app: gpu-monitor
    spec:
      nodeSelector:
        gpu: "true"              # Only run on nodes labeled gpu=true
      containers:
      - name: gpu-monitor
        image: nvidia/gpu-monitor:latest
```

```bash
# Label a node
kubectl label node node-1 gpu=true

# Now only node-1 will get the gpu-monitor pod
```

### DaemonSets Already Running in Your Cluster

Kubernetes itself uses DaemonSets! Check it out:

```bash
kubectl get daemonsets -n kube-system
# NAME         DESIRED   CURRENT   READY
# kube-proxy   3         3         3       # <-- Network proxy on every node
# calico-node  3         3         3       # <-- CNI plugin (if using Calico)
```

---

## Part 2: Jobs

### What Is a Job?

A Job creates one or more pods and ensures they **run to completion**. Unlike Deployments (which restart pods forever), a Job's pod runs, finishes its work, and stops.

```
Deployment Pod:  Start --> Run --> Crash --> Restart --> Run --> Crash --> Restart...
                 (keeps running forever)

Job Pod:         Start --> Run --> Complete --> Done!
                 (runs once, then stops)
```

### Why Do We Need Jobs?

Real-world use cases:
- Database migrations
- Batch processing (process 10,000 images)
- Sending bulk emails
- Data export/import
- Running tests
- One-time cleanup tasks

### Basic Job YAML

```yaml
# job-basic.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-job
spec:
  template:
    spec:
      containers:
      - name: hello
        image: busybox
        command: ["sh", "-c", "echo 'Hello from Job!' && sleep 5 && echo 'Job done!'"]
      restartPolicy: Never       # Jobs must use Never or OnFailure (not Always)
```

> **Important:** Jobs require `restartPolicy: Never` or `restartPolicy: OnFailure`. You can't use `Always` because the pod needs to be able to stop.

### Working with Jobs

```bash
# Create the job
kubectl apply -f job-basic.yaml

# Watch the job
kubectl get jobs -w
# NAME        COMPLETIONS   DURATION   AGE
# hello-job   0/1           5s         5s
# hello-job   1/1           12s        12s    # <-- completed!

# See the pod created by the job
kubectl get pods
# NAME              READY   STATUS      RESTARTS   AGE
# hello-job-abc12   0/1     Completed   0          30s

# Check the logs
kubectl logs hello-job-abc12
# Hello from Job!
# Job done!

# Delete the job (also deletes the pod)
kubectl delete job hello-job
```

### Job with Multiple Completions

What if you need to run the same task multiple times (e.g., process 5 batches)?

```yaml
# job-completions.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-job
spec:
  completions: 5               # Run 5 pods total (one after another)
  template:
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["sh", "-c", "echo Processing batch... && sleep 3"]
      restartPolicy: Never
```

```
Without parallelism (completions: 5):

  Pod 1: [===] Done
  Pod 2:        [===] Done
  Pod 3:               [===] Done
  Pod 4:                      [===] Done
  Pod 5:                             [===] Done

  Total time: 5 x 3s = ~15 seconds
```

### Job with Parallelism

Run multiple pods at the same time to speed things up:

```yaml
# job-parallel.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-job
spec:
  completions: 6               # Need 6 successful completions total
  parallelism: 3               # Run 3 pods at the same time
  template:
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["sh", "-c", "echo Processing batch... && sleep 3"]
      restartPolicy: Never
```

```
With parallelism: 3, completions: 6:

  Pod 1: [===] Done
  Pod 2: [===] Done        (3 at a time)
  Pod 3: [===] Done
  Pod 4:        [===] Done
  Pod 5:        [===] Done  (next 3)
  Pod 6:        [===] Done

  Total time: 2 batches x 3s = ~6 seconds (much faster!)
```

### Handling Failures with backoffLimit

What if a Job pod fails? By default, Kubernetes retries up to 6 times:

```yaml
# job-with-backoff.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: flaky-job
spec:
  backoffLimit: 4              # Retry up to 4 times before marking as Failed
  activeDeadlineSeconds: 60    # Give up after 60 seconds total
  template:
    spec:
      containers:
      - name: worker
        image: busybox
        command: ["sh", "-c", "echo Trying... && exit 1"]  # Always fails
      restartPolicy: Never
```

```bash
# Watch the retries
kubectl get pods -w
# NAME              READY   STATUS    AGE
# flaky-job-abc12   0/1     Error     5s
# flaky-job-def34   0/1     Error     15s    # retry 1 (backoff delay)
# flaky-job-ghi56   0/1     Error     35s    # retry 2 (longer delay)
# flaky-job-jkl78   0/1     Error     75s    # retry 3
# flaky-job-mno90   0/1     Error     155s   # retry 4 -- backoffLimit reached!

kubectl get jobs
# NAME        COMPLETIONS   DURATION   AGE
# flaky-job   0/1           3m         3m     # Failed!
```

### Key Job Fields Summary

| Field | Default | Description |
|-------|---------|-------------|
| `completions` | 1 | Total number of successful pod completions needed |
| `parallelism` | 1 | Max number of pods running at the same time |
| `backoffLimit` | 6 | Number of retries before marking Job as failed |
| `activeDeadlineSeconds` | none | Max total time for the Job |
| `ttlSecondsAfterFinished` | none | Auto-delete Job N seconds after completion |

### Auto-Cleanup Finished Jobs

```yaml
spec:
  ttlSecondsAfterFinished: 300   # Delete this Job 5 minutes after it finishes
```

---

## Part 3: CronJobs

### What Is a CronJob?

A CronJob creates **Jobs on a schedule**, just like Linux `cron`. It's perfect for recurring tasks.

```
CronJob (schedule: "0 2 * * *")
  │
  ├── 2:00 AM Day 1 --> Creates Job --> Job creates Pod --> Runs --> Done
  ├── 2:00 AM Day 2 --> Creates Job --> Job creates Pod --> Runs --> Done
  ├── 2:00 AM Day 3 --> Creates Job --> Job creates Pod --> Runs --> Done
  └── ...continues every day at 2 AM
```

### Cron Schedule Syntax

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6, Sunday = 0)
│ │ │ │ │
* * * * *
```

**Common examples:**

| Schedule | Meaning |
|----------|---------|
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour (at minute 0) |
| `0 2 * * *` | Every day at 2:00 AM |
| `0 0 * * 0` | Every Sunday at midnight |
| `0 9 1 * *` | 1st of every month at 9:00 AM |
| `30 8 * * 1-5` | Weekdays at 8:30 AM |

### CronJob YAML Example

```yaml
# cronjob-report.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-report
spec:
  schedule: "0 2 * * *"           # Every day at 2:00 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report
            image: busybox
            command: ["sh", "-c", "echo 'Generating daily report...' && date && sleep 5 && echo 'Report sent!'"]
          restartPolicy: OnFailure
```

### Working with CronJobs

```bash
# Create the CronJob
kubectl apply -f cronjob-report.yaml

# List CronJobs
kubectl get cronjobs
# NAME           SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# daily-report   0 2 * * *     False     0        <none>          10s

# Manually trigger a CronJob (don't wait for schedule)
kubectl create job --from=cronjob/daily-report daily-report-manual

# Watch for jobs being created
kubectl get jobs -w

# See pods from CronJob
kubectl get pods
# NAME                          READY   STATUS      AGE
# daily-report-28432100-abc12   0/1     Completed   5m

# Check logs
kubectl logs daily-report-28432100-abc12

# Delete the CronJob (also deletes all its Jobs)
kubectl delete cronjob daily-report
```

### CronJob Concurrency Policy

What happens if a new job triggers while the previous one is still running?

```yaml
spec:
  schedule: "*/1 * * * *"
  concurrencyPolicy: Forbid        # Options: Allow, Forbid, Replace
```

| Policy | Behavior |
|--------|----------|
| `Allow` (default) | Multiple jobs can run at the same time |
| `Forbid` | Skip the new job if the previous one is still running |
| `Replace` | Cancel the running job and start a new one |

```
concurrencyPolicy: Forbid

Time:  1:00    1:01    1:02    1:03
       [Job1=========]
               Skip!   [Job2===]
                               [Job3===]
```

### CronJob History Limits

By default, Kubernetes keeps the last 3 successful jobs and last 1 failed job:

```yaml
spec:
  successfulJobsHistoryLimit: 3    # Keep last 3 completed jobs (default)
  failedJobsHistoryLimit: 1        # Keep last 1 failed job (default)
```

### Complete CronJob Example

```yaml
# cronjob-db-backup.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
spec:
  schedule: "0 3 * * *"               # Every day at 3 AM
  concurrencyPolicy: Forbid           # Don't overlap backups
  successfulJobsHistoryLimit: 7       # Keep last 7 days of backups
  failedJobsHistoryLimit: 3           # Keep last 3 failures for debugging
  startingDeadlineSeconds: 300        # If missed by 5 min, skip it
  jobTemplate:
    spec:
      backoffLimit: 2                 # Retry twice on failure
      activeDeadlineSeconds: 3600     # Timeout after 1 hour
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15
            command:
            - /bin/sh
            - -c
            - |
              echo "Starting backup at $(date)"
              pg_dump -h $DB_HOST -U $DB_USER $DB_NAME > /backup/db-$(date +%Y%m%d).sql
              echo "Backup complete!"
            env:
            - name: DB_HOST
              value: "postgres-service"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DB_NAME
              value: "myapp"
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
          restartPolicy: OnFailure
```

### Suspending a CronJob

You can temporarily pause a CronJob without deleting it:

```bash
# Suspend (pause)
kubectl patch cronjob db-backup -p '{"spec":{"suspend":true}}'

# Resume
kubectl patch cronjob db-backup -p '{"spec":{"suspend":false}}'
```

---

## Quick Comparison

```
┌──────────────────────────────────────────────────────────────────┐
│  Workload      │  Runs...            │  Example                 │
│────────────────│─────────────────────│──────────────────────────│
│  Deployment    │  Forever (N pods)   │  Web server, API         │
│  DaemonSet     │  1 per node         │  Log collector, monitor  │
│  Job           │  Once, then stops   │  DB migration, batch     │
│  CronJob       │  On a schedule      │  Nightly backup, report  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Key Takeaways

1. **DaemonSet** = one pod per node, automatically. Perfect for node-level agents like log collectors, monitoring, and network plugins
2. DaemonSets have no `replicas` field -- the number of pods equals the number of nodes
3. **Job** = run-to-completion workload. Pod runs, finishes, and stops
4. Use `completions` for multiple runs and `parallelism` to speed them up
5. `backoffLimit` controls how many times a failed Job retries
6. **CronJob** = scheduled Job using cron syntax (`minute hour day month weekday`)
7. `concurrencyPolicy` controls what happens when jobs overlap: `Allow`, `Forbid`, or `Replace`
8. Jobs require `restartPolicy: Never` or `OnFailure` (never `Always`)
9. Kubernetes itself uses DaemonSets internally (kube-proxy runs as a DaemonSet)
10. Use `ttlSecondsAfterFinished` on Jobs to auto-clean completed pods

---

## Practice / Homework

1. Create a DaemonSet that runs `nginx` on every node. Verify with `kubectl get pods -o wide`
2. Create a Job that prints the date and completes. Check the logs
3. Create a Job with `completions: 4` and `parallelism: 2`. Watch pods run in parallel
4. Create a CronJob that runs every 2 minutes. Observe Jobs being created automatically
5. Test `concurrencyPolicy: Forbid` -- make a CronJob with a long-running task and see what happens
6. Suspend and resume a CronJob using `kubectl patch`

---

**Previous:** [<-- Day 18 - Ingress Demo](../day18-ingress-demo/notes.md)
**Next:** [Day 20 - Resource Management & Autoscaling -->](../day20-resource-management/notes.md)
