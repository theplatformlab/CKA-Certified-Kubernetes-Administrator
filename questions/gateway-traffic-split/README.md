# Gateway API traffic splitting

**Context:** `kubectl config use-context {{CONTEXT}}`

The Gateway API CRDs and GatewayClass `exam-gateway` are installed. In namespace `gateway` the Services `web-v1` and `web-v2` (both port `80`) exist.

1. Create a Gateway named `web-gateway` in namespace `gateway`:
   - GatewayClass `exam-gateway`
   - one listener named `http`, protocol `HTTP`, port `80`, hostname `web.example.com`
2. Create an HTTPRoute named `web-route` in namespace `gateway`:
   - attached to `web-gateway`, hostname `web.example.com`
   - sends requests for path prefix `/` to `web-v1` (weight `80`) and `web-v2` (weight `20`), both on port `80`

## Hints

- The Gateway API docs (gateway-api.sigs.k8s.io) are allowed in the exam and have a traffic-splitting example.
- A Gateway listener needs name, protocol and port; hostname is optional.
- In the HTTPRoute, `parentRefs` points to the Gateway and `backendRefs` takes a `weight` per Service.

## Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: gateway
spec:
  gatewayClassName: exam-gateway
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: web.example.com
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: gateway
spec:
  parentRefs:
  - name: web-gateway
  hostnames:
  - web.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-v1
      port: 80
      weight: 80
    - name: web-v2
      port: 80
      weight: 20
```

```bash
k config use-context {{CONTEXT}}
k apply -f gateway.yaml
k -n gateway describe httproute web-route
```

No controller implements `exam-gateway`, so the Gateway's status stays `Unknown`. Only the resources are graded. On the real exam a controller (for example NGINX Gateway Fabric or Envoy Gateway) would program the routes. The Gateway API docs (gateway-api.sigs.k8s.io) are allowed during the exam.
