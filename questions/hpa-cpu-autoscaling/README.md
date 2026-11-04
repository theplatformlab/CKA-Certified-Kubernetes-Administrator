# HorizontalPodAutoscaler

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `web-app` in namespace `autoscale` runs with {{HPA_MIN}} replicas.

Create a HorizontalPodAutoscaler (`autoscaling/v2`) named `web-app` in namespace `autoscale` that:

- targets Deployment `web-app`
- keeps the average CPU utilization at `{{CPU}}%`
- scales between `{{HPA_MIN}}` and `{{HPA_MAX}}` replicas
- uses a scale-down stabilization window of `{{WINDOW}}` seconds

## Hints

- `kubectl autoscale deployment ... --min --max --cpu=<n>%` creates the basic HPA.
- Generate YAML with `$do` and add the `behavior.scaleDown.stabilizationWindowSeconds` field yourself.
- Use `apiVersion: autoscaling/v2`; `kubectl explain hpa.spec.behavior` shows the structure.

## Solution

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app
  namespace: autoscale
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: {{HPA_MIN}}
  maxReplicas: {{HPA_MAX}}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{CPU}}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: {{WINDOW}}
```

`k autoscale deploy web-app --cpu={{CPU}}% --min={{HPA_MIN}} --max={{HPA_MAX}} -n autoscale $do > hpa.yaml` gives you the skeleton. The `behavior` block has to be added by hand.
