# With Helm - The Same App as a Chart

The identical app from [`../without-helm`](../without-helm/), but packaged as a Helm chart. Everything you might change lives in **`webapp/values.yaml`** - you never edit a template.

```
webapp/
  Chart.yaml            # chart + app version
  values.yaml           # all the knobs (replicas, image, message, probes...)
  values-prod.yaml      # only the prod overrides
  templates/
    _helpers.tpl        # reusable name/label snippets
    configmap.yaml      # HTML, values filled in
    deployment.yaml     # replicas/image/probes from values
    service.yaml
    NOTES.txt           # printed after install
```

## Validate before installing (no cluster needed)

```bash
cd with-helm
helm lint ./webapp                       # check for chart errors
helm template demo ./webapp | head -40   # render the YAML locally to eyeball it
```

## Install

```bash
kubectl create namespace demo-helm

# install the chart as a release named "webapp-dev"
helm install webapp-dev ./webapp -n demo-helm

helm list -n demo-helm                   # <-- Helm TRACKS your release + revision
kubectl get pods -l release=webapp-dev -n demo-helm
```

## See it

```bash
kubectl port-forward svc/webapp-dev-webapp 8080:80 -n demo-helm
# open http://localhost:8080  -> "Deployed WITH Helm"
```

## The payoff - change things with one command (no YAML edits)

```bash
# scale to 5 + new message, in one line:
helm upgrade webapp-dev ./webapp -n demo-helm \
  --set replicaCount=5 --set message="Now with 5 replicas"

helm history webapp-dev -n demo-helm     # revision 1, 2, ...
```

## Roll back a bad deploy - one command

```bash
helm rollback webapp-dev 1 -n demo-helm  # back to revision 1
helm history webapp-dev -n demo-helm
```

## Deploy a prod copy - one small values file (not a copied folder)

```bash
helm install webapp-prod ./webapp -n demo-helm -f ./webapp/values-prod.yaml
# 5 replicas, "PROD" message - same chart, different values
```

## Clean up

```bash
helm uninstall webapp-dev webapp-prod -n demo-helm
kubectl delete namespace demo-helm
```

---

## What Helm Gave You Here

- **One place to change anything** (`values.yaml`) - no template edits.
- **`helm list` / `helm history`** - you always know what is deployed and at which revision.
- **`helm upgrade` / `helm rollback`** - versioned changes and one-command recovery.
- **`-f values-prod.yaml`** - environments without copying files.
- **`checksum/config` annotation** - config changes auto-restart pods (the raw version needed a manual `rollout restart`).

Compare with the manual pain in [`../without-helm/README.md`](../without-helm/README.md).
