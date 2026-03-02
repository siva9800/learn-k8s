# EKS Managed Node Groups - Deep Dive

## What Are Managed Node Groups?

AWS manages EC2 instances (worker nodes) for you. **No extra cost** - you pay normal EC2 pricing.

```
┌─── What AWS Does for You (FREE) ───┐
│                                      │
│  ✅ Provisions EC2 and joins to      │
│     cluster automatically            │
│  ✅ OS patching & security updates   │
│  ✅ Graceful node draining during    │
│     K8s version upgrades             │
│  ✅ One-click K8s version upgrades   │
│  ✅ ASG with min/max boundaries      │
│  ✅ Health monitoring & auto-replace │
│     unhealthy nodes                  │
│                                      │
│  You pay ZERO extra for "managed"    │
│  Same EC2 price as self-managed!     │
└──────────────────────────────────────┘
```

---

## Cost Breakdown

```
EKS Costs:
├── Control Plane:          $0.10/hr  = ~$73/month (fixed, always)
│
├── Worker Nodes (EC2):     Normal EC2 pricing
│   ├── t3.medium  (2 vCPU, 4GB):   ~$30/month each
│   ├── t3.large   (2 vCPU, 8GB):   ~$60/month each
│   └── t3.xlarge  (4 vCPU, 16GB):  ~$120/month each
│
├── EBS Storage:            ~$0.10/GB/month
├── NAT Gateway:            ~$32/month
└── Load Balancer:          ~$16/month each

Example: 2-node cluster (t3.medium):
  $73 (control plane) + $60 (2 nodes) + $32 (NAT) = ~$165/month minimum
```

**"Managed" is FREE** - AWS doesn't charge anything extra for:
- Node provisioning
- OS patching
- Draining during upgrades
- Health monitoring
- ASG integration

---

## What Is Node Draining?

When a node needs to be removed (K8s upgrade, scaling down, maintenance), you can't just kill it - pods are running on it!

```
WITHOUT draining (bad):
  Node killed → All pods die instantly → Users see errors 💀

WITH draining (managed node groups do this AUTOMATICALLY):

  Step 1: Node marked as "unschedulable"
          (no NEW pods go here)

  Step 2: Existing pods gracefully moved to other nodes
          (respects Pod Disruption Budgets)

  Step 3: Node is empty → safely removed

  Step 4: Users see ZERO downtime ✅
```

```
BEFORE drain:                      AFTER drain:
┌─── Node 1 ───┐                 ┌─── Node 1 ───┐
│ Pod-A  Pod-B  │                 │   (empty)     │ ← safe to remove
│ Pod-C         │                 │ unschedulable │
└───────────────┘                 └───────────────┘
┌─── Node 2 ───┐                 ┌─── Node 2 ───┐
│ Pod-D         │                 │ Pod-D  Pod-A  │ ← pods moved here
└───────────────┘                 │ Pod-B  Pod-C  │
                                  └───────────────┘
```

### When Does Draining Happen?

| Scenario | Who Drains? |
|----------|------------|
| K8s version upgrade | **AWS does it automatically** (managed node groups) |
| Scale down (remove node) | **Cluster Autoscaler** does it automatically |
| Manual maintenance | You run `kubectl drain <node>` manually |
| Self-managed nodes | **Always manual** - you do everything |

---

## Managed vs Self-Managed vs Fargate

| Feature | Managed Node Groups | Self-Managed Nodes | Fargate |
|---------|-------------------|-------------------|---------|
| **Who manages nodes?** | AWS | You | No nodes (serverless) |
| **Extra cost?** | No (same EC2 price) | Same EC2 price | Per pod pricing |
| **OS patching** | Automatic | Manual | N/A |
| **Node draining** | Automatic | Manual | N/A |
| **K8s upgrades** | One-click | Manual (risky) | Automatic |
| **DaemonSets** | Yes | Yes | **No** |
| **GPU support** | Yes | Yes | **No** |
| **Custom AMI** | Limited | Full control | No |
| **Idle cost** | Yes (EC2 running) | Yes (EC2 running) | No (pay per pod) |
| **Recommendation** | **Default choice** | Only if custom needs | Small/simple apps |

---

## Key Takeaways

1. **Managed Node Groups** = AWS manages nodes, zero extra cost
2. **Draining** = gracefully moving pods before removing a node
3. **Managed groups drain automatically** during upgrades
4. **Always use managed** unless you need custom AMI
5. ASG min/max sets boundaries, but you need autoscaling to actually scale nodes

> For autoscaling details (HPA, Cluster Autoscaler, Karpenter): See [Day 20 - Autoscaling](../../day20-autoscaling/notes.md)

---

**Back to:** [EKS Notes](../notes.md)
