# Day 02 - Kubernetes Architecture

## Why This Matters

Before you start using Kubernetes, you need to understand **what's happening inside**. If you skip this, you'll struggle to debug problems later.

---

## Big Picture - The Cluster

A Kubernetes **cluster** has two types of machines (nodes):

```
┌──────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                         │
│                                                              │
│  ┌──────────────────┐    ┌──────────────┐ ┌──────────────┐  │
│  │   MASTER NODE     │    │ WORKER NODE 1│ │ WORKER NODE 2│  │
│  │   (Control Plane) │    │              │ │              │  │
│  │                   │    │ ┌──┐ ┌──┐    │ │ ┌──┐ ┌──┐   │  │
│  │  Decides WHAT     │    │ │P1│ │P2│    │ │ │P3│ │P4│   │  │
│  │  should happen    │    │ └──┘ └──┘    │ │ └──┘ └──┘   │  │
│  │                   │    │              │ │              │  │
│  │                   │    │ Runs the     │ │ Runs the     │  │
│  │                   │    │ actual apps  │ │ actual apps  │  │
│  └──────────────────┘    └──────────────┘ └──────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

> **Master Node** = The **brain** - makes all decisions
> **Worker Nodes** = The **hands** - do the actual work (run your containers)

---

## Master Node (Control Plane) Components

The master node has 4 main components:

### 1. API Server (`kube-apiserver`)

```
You (kubectl) ──→ API Server ──→ Rest of K8s
```

- **What:** The front door of Kubernetes. EVERYTHING goes through it.
- **Why:** Single entry point. When you type `kubectl get pods`, the request goes to API Server first.
- **Analogy:** The **receptionist** at a hospital. Every request goes through them first.

### 2. etcd

- **What:** A key-value database that stores ALL cluster data.
- **Why:** K8s needs to remember: how many pods are running? what version? which node? All stored in etcd.
- **Analogy:** The **hospital's record room**. All patient records, room assignments, everything is stored here.
- **Important:** If etcd is lost, your entire cluster's configuration is lost. Always back it up!

### 3. Scheduler (`kube-scheduler`)

```
New Pod needs to run → Scheduler picks the best Worker Node
```

- **What:** Decides WHICH worker node should run a new pod.
- **Why:** Not all nodes are equal. Some have more CPU, some have more RAM. Scheduler picks the best fit.
- **Analogy:** The **room assignment desk** at a hospital. New patient arrives → checks which room has space → assigns room.

**How Scheduler Decides:**
- Does the node have enough CPU/RAM?
- Does the pod have any specific requirements (e.g., must run on a node with GPU)?
- Is the node already overloaded?

### 4. Controller Manager (`kube-controller-manager`)

- **What:** Runs background loops that check: "Is the actual state = desired state?"
- **Why:** You say "I want 3 pods". Controller checks: are there 3? If only 2, it creates 1 more.
- **Analogy:** The **hospital supervisor** who walks around checking: "Are all departments staffed properly?"

**Types of Controllers:**
| Controller | What It Does |
|-----------|-------------|
| ReplicaSet Controller | Ensures correct number of pod replicas |
| Deployment Controller | Manages rolling updates |
| Node Controller | Monitors node health |
| Job Controller | Manages one-time tasks |

---

## Worker Node Components

Each worker node has 3 main components:

### 1. Kubelet

- **What:** An agent running on every worker node. Talks to API Server.
- **Why:** API Server tells kubelet "run this pod", kubelet makes it happen.
- **Analogy:** The **nurse** on each hospital floor. Receives instructions from doctor, takes care of patients.

### 2. Kube-Proxy

- **What:** Handles networking on each node.
- **Why:** When a request comes for your app, kube-proxy routes it to the right pod.
- **Analogy:** The **hospital's internal phone system**. Routes calls to the correct department.

### 3. Container Runtime

- **What:** The software that actually runs containers (Docker, containerd, CRI-O).
- **Why:** K8s doesn't run containers itself. It tells the container runtime to do it.
- **Analogy:** The **medical equipment**. The nurse (kubelet) uses equipment (container runtime) to treat patients (run containers).

---

## How It All Works Together

Let's trace what happens when you run: `kubectl apply -f pod.yaml`

```
Step 1: kubectl sends request to API Server
         │
Step 2: API Server validates the request and stores it in etcd
         │
Step 3: Scheduler notices "there's a new pod with no node assigned"
         │
Step 4: Scheduler picks the best worker node → tells API Server
         │
Step 5: API Server tells the Kubelet on that worker node
         │
Step 6: Kubelet tells Container Runtime to pull image and start container
         │
Step 7: Container is running! Kubelet reports status back to API Server
         │
Step 8: API Server updates etcd with the pod's current status
```

---

## Complete Architecture Diagram

```
┌─────────────────── MASTER NODE ───────────────────┐
│                                                    │
│  ┌────────────┐  ┌──────────────────────────────┐ │
│  │            │  │      Controller Manager       │ │
│  │   etcd     │  │  (ReplicaSet, Deployment,     │ │
│  │ (database) │  │   Node, Job controllers)      │ │
│  │            │  └──────────────────────────────┘ │
│  └────────────┘                                   │
│        ↕            ┌──────────────┐              │
│  ┌────────────┐     │  Scheduler   │              │
│  │ API Server │ ←──→│  (picks      │              │
│  │ (gateway)  │     │   nodes)     │              │
│  └─────┬──────┘     └──────────────┘              │
└────────┼──────────────────────────────────────────┘
         │
    ─────┼──────────────────────────────────────
         │              NETWORK
    ─────┼──────────────────────────────────────
         │
┌────────┼───── WORKER NODE 1 ─────┐  ┌──── WORKER NODE 2 ────┐
│        ↓                          │  │                        │
│  ┌──────────┐                    │  │  ┌──────────┐          │
│  │ Kubelet  │                    │  │  │ Kubelet  │          │
│  └────┬─────┘                    │  │  └────┬─────┘          │
│       ↓                          │  │       ↓                │
│  ┌──────────┐  ┌──────────────┐  │  │  ┌──────────┐         │
│  │Container │  │  Kube-Proxy  │  │  │  │Container │         │
│  │ Runtime  │  │ (networking) │  │  │  │ Runtime  │         │
│  └────┬─────┘  └──────────────┘  │  │  └────┬─────┘         │
│       ↓                          │  │       ↓                │
│  ┌────┐ ┌────┐ ┌────┐           │  │  ┌────┐ ┌────┐        │
│  │Pod1│ │Pod2│ │Pod3│           │  │  │Pod4│ │Pod5│        │
│  └────┘ └────┘ └────┘           │  │  └────┘ └────┘        │
└──────────────────────────────────┘  └────────────────────────┘
```

---

## Summary Table

| Component | Where | What It Does |
|-----------|-------|-------------|
| API Server | Master | Front door - receives all requests |
| etcd | Master | Database - stores all cluster state |
| Scheduler | Master | Picks which node runs a new pod |
| Controller Manager | Master | Ensures desired state = actual state |
| Kubelet | Worker | Runs pods on the node |
| Kube-Proxy | Worker | Handles networking/routing |
| Container Runtime | Worker | Actually runs containers |

---

## Practice / Homework

1. Draw the Kubernetes architecture on paper from memory
2. Answer these questions:
   - What happens if etcd goes down?
   - Where does your app actually run - Master or Worker?
   - If you run `kubectl get pods`, which component handles your request first?
   - What's the difference between Scheduler and Controller Manager?
3. Run `kubectl get componentstatuses` (if you have a cluster) to see all components

---

**Previous:** [← Day 01 - Why Kubernetes?](../Day01-Why-Kubernetes/notes.md)
**Next:** [Day 03 - Setting Up K8s →](../Day03-Setup/notes.md)
