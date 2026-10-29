# Canary deployment behind one Service

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `release`, Deployment `shop-v1` (image `nginx:1.28`) runs {{TOTAL}} replicas behind Service `shop`. A new version is to be tested as a canary that gets about `{{PCT}}%` of the traffic.

1. Create a Deployment named `shop-v2` in namespace `release` with image `nginx:1.29` and pod labels `app=shop` and `version=v2`.
2. Keep {{TOTAL}} pods in total: `shop-v2` runs `{{V2}}` replicas and `shop-v1` runs `{{V1}}` replicas.
3. Service `shop` must send traffic to the pods of both Deployments. Do not create another Service.

## Hints

- `k -n release get deploy shop-v1 -o yaml` and `k -n release get svc shop -o wide`: which labels do the pods and the Service selector use?
- The Service selector must only contain the label that both versions share. Remove `version` from it.
- Export `shop-v1` with `-o yaml`, change the name, the `version` label (in the selector and in the template), the image and the replicas.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n release get svc shop -o jsonpath='{.spec.selector}'       # {"app":"shop","version":"v1"}
k -n release get deploy shop-v1 -o yaml > v2.yaml
```

```yaml
# v2.yaml, cleaned up (no status, uid, resourceVersion, ...)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-v2
  namespace: release
spec:
  replicas: {{V2}}
  selector:
    matchLabels:
      app: shop
      version: v2
  template:
    metadata:
      labels:
        app: shop
        version: v2
    spec:
      containers:
      - name: shop
        image: nginx:1.29
```

```bash
k apply -f v2.yaml
k -n release scale deploy shop-v1 --replicas={{V1}}
k -n release patch svc shop --type=json -p '[{"op":"remove","path":"/spec/selector/version"}]'
k -n release get endpointslices -l kubernetes.io/service-name=shop -o wide   # {{TOTAL}} endpoints
k -n release get pods -L version
```

A Service spreads connections roughly evenly over its ready endpoints, so the share of traffic follows the share of pods: {{V2}} of {{TOTAL}} is {{PCT}}%. Each Deployment's own selector must stay unique (with `version`), otherwise the two Deployments would fight over each other's pods. `k create deployment shop-v2 --image=nginx:1.29` would label the pods `app=shop-v2`, so the generated YAML needs its labels changed anyway. `k edit svc shop` and deleting the `version` line works as well as the patch.
