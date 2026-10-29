# Exercise 15 — Gateway API: Gateway and HTTPRoute

> **Medium** | ~20 min | Domain: Services & Networking (20%)
>
> Related: [Gateway API skeleton](../../skeletons/gateway-api.yaml) | [README — Services & Networking](../../README.md#domain-5--services--networking-20)

Gateway API is GA in v1.35 and replaces classic Ingress for modern traffic management. Set up a Gateway and route HTTP traffic to a backend service.

## Tasks

Work in namespace `exercise-15` (`./scripts/lab.sh setup 15` creates it, installs the Gateway API v1.6.3 standard CRDs and a GatewayClass). The lab cluster runs no Gateway controller, so the check validates the object specs and the backend Service — not traffic through the Gateway.

1. Find the GatewayClass that exists in the cluster (in the exam it depends on the installed controller)
2. Create a Gateway named `web-gateway` in namespace `exercise-15`:
   - Reference the existing GatewayClass
   - One listener named `http` on port 80, protocol HTTP
3. Create a Deployment named `web` with image `nginx:1.28` and 2 replicas
4. Expose it with a ClusterIP Service named `web-svc` on port 80
5. Create an HTTPRoute named `web-route` that:
   - References `web-gateway` as the parent
   - Matches path prefix `/`
   - Routes to `web-svc` on port 80
6. Inspect the Gateway and HTTPRoute status. With a real controller the Gateway shows `Programmed: True` and the HTTPRoute lists `web-gateway` under `status.parents`; in this lab no controller reconciles the class, so the status stays `Unknown` ("Waiting for controller")

Validate with `./scripts/lab.sh check 15`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k get gatewayclass` to find the available class
- The Gateway `listeners[].protocol` is `HTTP`, not `TCP`
- HTTPRoute `parentRefs` must match the Gateway name and namespace
- Check status: `k get gateway web-gateway -n exercise-15 -o yaml`
- If no GatewayClass is installed, use Envoy Gateway or Cilium

</details>

## What tripped me up

> The `parentRefs.name` in HTTPRoute must match the Gateway name EXACTLY. I had `web-gw` in the HTTPRoute but the Gateway was called `web-gateway`. No error — the HTTPRoute just never attached to anything. Traffic goes nowhere and there's no obvious indication why. I spent 10 minutes checking backend pods and service selectors when the problem was a one-word typo in parentRefs.
>
> Also: Gateway API won't work without a GatewayClass controller actually installed. On a fresh cluster there might be no GatewayClass at all. `k get gatewayclass` — if it's empty, you need to install a controller first. The exam environment should have one, but verify before writing YAML.

## Verify

```bash
./scripts/lab.sh check 15
```

Manual checks:

```bash
# Gateway: CLASS cka-lab (PROGRAMMED stays Unknown without a controller)
k get gateway web-gateway -n exercise-15

# HTTPRoute: parentRefs and backendRefs
k get httproute web-route -n exercise-15 -o yaml

# Backend pods running and reachable
k get pods -n exercise-15
k -n exercise-15 run t --image=busybox:1.37 --rm -it --restart=Never -- \
  wget -qO- web-svc.exercise-15.svc.cluster.local
```

## Cleanup

```bash
./scripts/lab.sh cleanup 15
```

Cleanup also deletes the `cka-lab` GatewayClass and the Gateway API CRDs (if no other Gateway API objects are left).

<details>
<summary>Solution</summary>

```bash
# Check GatewayClass
k get gatewayclass
# In this lab: cka-lab. In other clusters e.g. "eg" for Envoy Gateway or "cilium" for Cilium
```

```yaml
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: exercise-15
spec:
  gatewayClassName: cka-lab    # the GatewayClass from k get gatewayclass
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
```

```bash
# Deploy backend
k create deployment web -n exercise-15 --image=nginx:1.28 --replicas=2
k expose deployment web -n exercise-15 --port=80 --target-port=80 --name=web-svc
```

```yaml
# httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: exercise-15
spec:
  parentRefs:
  - name: web-gateway
    namespace: exercise-15
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-svc
      port: 80
```

```bash
k apply -f gateway.yaml
k apply -f httproute.yaml

# Check Gateway status
k get gateway web-gateway -n exercise-15
k get gateway web-gateway -n exercise-15 -o yaml | grep -A5 "conditions"

# Check HTTPRoute
k get httproute web-route -n exercise-15 -o yaml | grep -A5 "parents"
```

</details>
