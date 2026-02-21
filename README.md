# Learn Kubernetes - Day-Wise Notes for Beginners

A complete beginner-friendly, day-by-day Kubernetes learning guide. Each day builds on the previous one, explaining **why** we need each concept before diving into **how**.

---

## Who Is This For?

- Complete beginners who know basic Linux and Docker
- Students who want to understand Kubernetes end-to-end
- Anyone preparing for CKA/CKAD exams

## Prerequisites

- Basic Linux commands (cd, ls, cat, vim)
- Docker fundamentals (images, containers, Dockerfile)
- A laptop with 4GB+ RAM

---

## Day-Wise Roadmap (25 Days)

| Day | Topic | Type | What You'll Learn |
|-----|-------|------|-------------------|
| [Day 01](Day01-Why-Kubernetes/notes.md) | **Why Kubernetes?** | Theory | Problems with traditional deployment, why containers alone aren't enough |
| [Day 02](Day02-Architecture/notes.md) | **Kubernetes Architecture** | Theory | Master node, Worker node, all internal components |
| [Day 03](Day03-Setup/notes.md) | **Setting Up K8s** | Setup | Install Minikube, kubectl, and run your first cluster |
| [Day 04](Day04-Pods/notes.md) | **Pods** | Theory + Lab | The smallest unit in K8s, create and manage Pods |
| [Day 05](Day05-ReplicaSets/notes.md) | **ReplicaSets** | Theory + Lab | Running multiple copies of your app, self-healing |
| [Day 06](Day06-Deployments/notes.md) | **Deployments** | Theory + Lab | Rolling updates, rollbacks, zero-downtime deployments |
| [Day 07](Day07-Services/notes.md) | **Services & Networking** | Theory | ClusterIP, NodePort, LoadBalancer, ExternalName, Headless |
| [Day 08](Day08-Services-Demo/notes.md) | **Services Demo** | Hands-On | Demo all 5 service types, DNS discovery, load balancing |
| [Day 09](Day09-Namespaces/notes.md) | **Namespaces** | Theory + Lab | Organizing and isolating resources in a cluster |
| [Day 10](Day10-ConfigMaps-Secrets/notes.md) | **ConfigMaps & Secrets** | Theory + Lab | Externalizing configuration, managing sensitive data |
| [Day 11](Day11-Volumes/notes.md) | **Volumes & Persistent Storage** | Theory | Data persistence, PV, PVC, StorageClass |
| [Day 12](Day12-Volumes-Demo/notes.md) | **Volumes Demo** | Hands-On | Prove data survives pod deletion, PV/PVC binding, MySQL demo |
| [Day 13](Day13-Ingress/notes.md) | **Ingress** | Theory | HTTP routing, domain-based routing, TLS |
| [Day 14](Day14-Ingress-Demo/notes.md) | **Ingress Demo** | Hands-On | Path-based routing, host-based routing, TLS setup |
| [Day 15](Day15-DaemonSets-Jobs-CronJobs/notes.md) | **DaemonSets, Jobs & CronJobs** | Theory + Lab | Running pods on every node, batch processing |
| [Day 16](Day16-Resource-Management/notes.md) | **Resource Management & Autoscaling** | Theory + Lab | CPU/Memory limits, HPA, VPA |
| [Day 17](Day17-RBAC-Security/notes.md) | **RBAC & Security** | Theory + Lab | Role-Based Access Control, Service Accounts |
| [Day 18](Day18-StatefulSets/notes.md) | **StatefulSets** | Theory | Running stateful applications like databases |
| [Day 19](Day19-StatefulSets-Demo/notes.md) | **StatefulSets Demo** | Hands-On | Ordered creation, headless DNS, per-pod storage |
| [Day 20](Day20-Network-Policies/notes.md) | **Network Policies** | Theory + Lab | Controlling traffic between pods |
| [Day 21](Day21-Helm/notes.md) | **Helm** | Theory + Lab | Package manager for Kubernetes |
| [Day 22](Day22-Monitoring-Logging/notes.md) | **Monitoring & Logging** | Theory | Prometheus, Grafana, log collection |
| [Day 23](Day23-Monitoring-Demo/notes.md) | **Monitoring Demo** | Hands-On | Install Prometheus+Grafana, dashboards, PromQL, load test |
| [Day 24](Day24-CICD/notes.md) | **CI/CD with Kubernetes** | Theory + Lab | Automating deployments with pipelines, ArgoCD |
| [Day 25](Day25-Project-BestPractices/notes.md) | **Real-World Project & Best Practices** | Hands-On | Deploy a full 3-tier application end-to-end |

---

## How to Use This Repo

1. **Follow day by day** - don't skip days, each concept builds on the previous
2. **Type the commands yourself** - don't just copy-paste, type them to build muscle memory
3. **Break things on purpose** - delete pods, crash containers, see how K8s recovers
4. **Read the YAML files** - understanding YAML structure is key to mastering K8s

## Quick Reference - kubectl Cheat Sheet

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes

# Working with resources
kubectl get pods / deployments / services / all
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- /bin/bash

# Create / Apply / Delete
kubectl apply -f <file.yaml>
kubectl delete -f <file.yaml>
kubectl delete pod <pod-name>

# Debugging
kubectl get events
kubectl top pods
kubectl get pods -o wide
```

---

**Happy Learning!** Start with [Day 01 - Why Kubernetes?](Day01-Why-Kubernetes/notes.md)
