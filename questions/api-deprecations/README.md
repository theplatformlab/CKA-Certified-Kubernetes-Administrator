# Manifests with removed API versions

**Context:** `kubectl config use-context {{CONTEXT}}`

The manifests of an old application are in `{{WORKDIR}}/legacy-apps/`: a Service, a Deployment, a HorizontalPodAutoscaler, a CronJob and an Ingress, all for namespace `legacy-apps`. Applying them fails on this cluster because some of them use API versions that have been removed.

1. Update the files in place so that every one of them uses an API version the cluster serves, changing whatever fields the new version requires. The objects must keep their names and settings (replicas, image, schedule, autoscaling limits, host, path, backend).
2. Apply all of them. The Deployment's pods must be Ready.

## Hints

- `k apply -f {{WORKDIR}}/legacy-apps/` tells you which kinds have no match for their version; `k api-resources | grep -iE 'deploy|cronjob|horizontal|ingress'` lists the versions served now.
- `k explain <kind> --api-version=<group/version>` and `k explain ingress.spec.rules.http.paths.backend` show the current fields.
- `apps/v1` requires `spec.selector`; Ingress `networking.k8s.io/v1` requires `pathType` and writes the backend as `service.name` / `service.port.number`.

## Solution

```bash
k config use-context {{CONTEXT}}
cd {{WORKDIR}}/legacy-apps
k apply -f .     # no matches for kind "Deployment" in version "extensions/v1beta1", ...
k api-resources | grep -E 'deployments|horizontalpod|cronjobs|ingresses '
# deployments  apps/v1 ... horizontalpodautoscalers autoscaling/v2 ... cronjobs batch/v1 ... ingresses networking.k8s.io/v1
```

| File | Old | New | Other changes |
|---|---|---|---|
| deployment.yaml | `extensions/v1beta1` | `apps/v1` | add `spec.selector.matchLabels: {app: report-ui}` |
| hpa.yaml | `autoscaling/v2beta2` | `autoscaling/v2` | none |
| cronjob.yaml | `batch/v1beta1` | `batch/v1` | none |
| ingress.yaml | `networking.k8s.io/v1beta1` | `networking.k8s.io/v1` | `pathType`, new backend format |

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-ui
  namespace: legacy-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: report-ui
  template:
    ...
---
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: report-ui
  namespace: legacy-apps
spec:
  rules:
  - host: reports.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: report-ui
            port:
              number: 80
```

```bash
sed -i 's#autoscaling/v2beta2#autoscaling/v2#' hpa.yaml
sed -i 's#batch/v1beta1#batch/v1#' cronjob.yaml
k apply -f .
k -n legacy-apps get deploy,hpa,cronjob,ingress
k -n legacy-apps rollout status deploy report-ui
```

Removed in: `extensions/v1beta1` and `apps/v1beta1|2` Deployments in 1.16, `networking.k8s.io/v1beta1` Ingress in 1.22, `batch/v1beta1` CronJob in 1.25, `autoscaling/v2beta2` in 1.26. The [deprecation guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/) lists them all. The `kubectl convert` plugin can rewrite a manifest, but it is not installed by default; editing by hand is quick enough.
