# Without Helm - Raw Kubernetes Manifests

Deploy the app with plain `kubectl`. Three files: a ConfigMap (the HTML), a Deployment (nginx), and a Service.

## Deploy

```bash
# 1. A namespace to keep the demo tidy
kubectl create namespace demo-manual

# 2. Apply all three manifests
kubectl apply -f . -n demo-manual

# 3. Watch the pods come up (readiness gates them to Ready)
kubectl get pods -n demo-manual -w
# webapp-xxxx   1/1   Running   ...   (2 replicas)
```

## See it

```bash
kubectl port-forward svc/webapp 8080:80 -n demo-manual
# open http://localhost:8080  -> "Deployed WITHOUT Helm"
```

## Now feel the pain

Try to change something - say, **3 replicas** and a **new message**:

```bash
# You must hand-edit the YAML:
#   - open deployment.yaml, change replicas: 2 -> 3
#   - open configmap.yaml,  change the <p> text and "Replicas: 2"
# then re-apply:
kubectl apply -f . -n demo-manual
kubectl rollout restart deployment/webapp -n demo-manual   # pods must restart to remount the new ConfigMap
```

For a **prod** copy you would duplicate this whole folder and edit every file. There is no `list`, no versioned `upgrade`, and no one-command `rollback`. That is exactly what Helm fixes - see [`../with-helm/`](../with-helm/).

## Clean up

```bash
kubectl delete -f . -n demo-manual
kubectl delete namespace demo-manual
```

---

## The Downsides You Just Experienced

- **No parameters** - every change means editing YAML.
- **No environments** - dev vs prod = copy + edit files.
- **No release tracking** - nothing tells you what version is deployed.
- **No easy rollback** - you revert files by hand and re-apply.
- **Config changes need a manual restart** to be picked up.

Next: [Deploy the same app WITH Helm](../with-helm/README.md)
