# Install a local Helm chart

**Context:** `kubectl config use-context {{CONTEXT}}`

A Helm chart is located at `{{WORKDIR}}/helm-charts/monitoring`.

Install it as release `monitoring-stack` in namespace `monitoring` and create the namespace if needed. Override these chart values:

- `replicaCount` = `3`
- `persistence.enabled` = `true`
- `persistence.size` = `2Gi`

Do not modify the chart files. All replicas must be Ready.

## Hints

- `helm show values <chart-dir>` lists the value names you can override.
- `helm install <release> <chart-dir> -n <ns> --create-namespace --set a=b --set c.d=e`
- Wrong values after install? `helm upgrade` the release with the right `--set` flags instead of reinstalling.

## Solution

```bash
k config use-context {{CONTEXT}}
helm show values {{WORKDIR}}/helm-charts/monitoring      # find the value names
helm install monitoring-stack {{WORKDIR}}/helm-charts/monitoring \
  -n monitoring --create-namespace \
  --set replicaCount=3 \
  --set persistence.enabled=true \
  --set persistence.size=2Gi

helm -n monitoring list
helm -n monitoring get values monitoring-stack
k -n monitoring get deploy,pvc
```

If you installed it with the wrong values, fix them with `helm upgrade monitoring-stack ... --set ...`, then `--reuse-values`. Don't edit `values.yaml`.
