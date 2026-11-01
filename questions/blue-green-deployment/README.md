# Blue/green deployment

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `web-release`, Deployment `web-blue` (image `nginx:1.28`, {{REPLICAS}} replicas) serves all traffic of Service `web`. Release the new version with a blue/green switch:

1. Create a Deployment `web-green` with image `nginx:1.29`, `{{REPLICAS}}` replicas and pod labels `app=web` and `version=green`.
2. When all green pods are ready, switch Service `web` so that it sends all traffic to the green pods and none to the blue ones. Do not create another Service.
3. Scale `web-blue` down to 0 replicas. Do not delete it: it is kept for a quick switch back.

## Hints

- `k -n web-release get svc web -o wide` shows which labels the Service selects.
- Copy `web-blue` with `-o yaml`; change name, `version` label (selector and template), image. `k create deploy` would label the pods `app=web-green`.
- Switch with `k patch svc` or `k edit svc`: only the `version` value of the selector changes.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n web-release get deploy web-blue -o yaml > green.yaml
```

```yaml
# green.yaml, cleaned up (no status, uid, resourceVersion, ...)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-green
  namespace: web-release
spec:
  replicas: {{REPLICAS}}
  selector:
    matchLabels:
      app: web
      version: green
  template:
    metadata:
      labels:
        app: web
        version: green
    spec:
      containers:
      - name: web
        image: nginx:1.29
        ports:
        - containerPort: 80
```

```bash
k apply -f green.yaml
k -n web-release rollout status deploy web-green
k -n web-release patch svc web -p '{"spec":{"selector":{"app":"web","version":"green"}}}'
k -n web-release get endpointslices -l kubernetes.io/service-name=web -o wide   # only green pod IPs
k -n web-release scale deploy web-blue --replicas=0

# switching back would be: scale web-blue up, wait, patch the selector to version=blue
```

Unlike a canary (both versions behind one selector), blue/green flips all traffic at once by changing the Service selector, and the old version stays deployed until you are confident. Waiting for `rollout status` before the switch ensures the Service never points at pods that aren't ready.
