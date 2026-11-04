# Namespace resource governance

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `batch-jobs`:

1. Create a ResourceQuota named `batch-quota`:
   - `requests.cpu: 10`, `requests.memory: 20Gi`
   - `limits.cpu: 10`, `limits.memory: 20Gi`
   - `pods: 20`
2. Create a LimitRange named `batch-limits` for type `Container`:
   - minimum `500m` CPU and `256Mi` memory
   - maximum `4` CPU and `8Gi` memory
   - default request and default limit both `500m` CPU and `256Mi` memory

A container requesting `5` CPUs must then be rejected.

## Hints

- `kubectl create quota ... --hard=requests.cpu=...,pods=...`
- The LimitRange YAML (type Container, min/max/default/defaultRequest) is on the LimitRange page on kubernetes.io.
- Test with `kubectl run ... --dry-run=server` and an `--overrides` with large requests.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n batch-jobs create quota batch-quota \
  --hard=requests.cpu=10,requests.memory=20Gi,limits.cpu=10,limits.memory=20Gi,pods=20
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: batch-limits
  namespace: batch-jobs
spec:
  limits:
  - type: Container
    min:
      cpu: 500m
      memory: 256Mi
    max:
      cpu: "4"
      memory: 8Gi
    defaultRequest:
      cpu: 500m
      memory: 256Mi
    default:
      cpu: 500m
      memory: 256Mi
```

```bash
k apply -f lr.yaml
k -n batch-jobs run big --image=busybox:1.37 \
  --overrides='{"spec":{"containers":[{"name":"big","image":"busybox:1.37","resources":{"requests":{"cpu":"5"},"limits":{"cpu":"5"}}}]}}'
# Error ... maximum cpu usage per Container is 4, but limit is 5
```
