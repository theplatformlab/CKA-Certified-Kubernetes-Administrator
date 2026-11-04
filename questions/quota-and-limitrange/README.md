# ResourceQuota and LimitRange

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `test` uses too many resources. In namespace `test`:

1. Create a ResourceQuota named `compute-quota` with these limits:
   - `requests.cpu: 4`
   - `requests.memory: 8Gi`
   - `limits.cpu: 4`
   - `limits.memory: 8Gi`
2. Create a LimitRange named `container-limits` for type `Container`:
   - default request: `100m` CPU, `128Mi` memory
   - default limit: `200m` CPU, `256Mi` memory
   - minimum: `100m` CPU, `128Mi` memory
   - maximum: `1` CPU, `1Gi` memory

Afterwards, a pod whose container requests `2` CPUs and `2Gi` memory must be rejected. A pod without any resources must be admitted with the defaults.

## Hints

- `kubectl create quota <name> --hard=requests.cpu=...,limits.memory=...`
- There is no `kubectl create limitrange`: take the YAML from the LimitRange page on kubernetes.io.
- `default` is the default limit and `defaultRequest` the default request. `min` and `max` reject containers outside the range.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n test create quota compute-quota \
  --hard=requests.cpu=4,requests.memory=8Gi,limits.cpu=4,limits.memory=8Gi
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-limits
  namespace: test
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    default:
      cpu: 200m
      memory: 256Mi
    min:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: "1"
      memory: 1Gi
```

The 2-CPU pod is rejected by the LimitRange (`maximum cpu usage per Container is 1`), not by the quota. Once the quota covers `limits.*`, every pod has to declare limits. The LimitRange defaults fill them in, which is why a pod without resources is still admitted.
