# Migrate an Ingress to an HTTPRoute

**Context:** `kubectl config use-context {{CONTEXT}}`

The media platform in namespace `media-hub` moves from Ingress to the Gateway API. The current routing is the Ingress `media`, its manifest is saved in `{{WORKDIR}}/media-ingress.yaml`. The Gateway API CRDs are installed, and the Gateway `media-gateway` (listener `http`, port `80`) exists in namespace `media-hub`.

Create an HTTPRoute named `media-route` in namespace `media-hub` that:

1. is attached to Gateway `media-gateway` and serves the same host as the Ingress
2. routes the same paths to the same Services and ports as the Ingress
3. additionally routes the path prefix `{{PREVIEW_PATH}}`: requests that carry the header `{{HEADER}}` with exactly the value `{{HEADER_VALUE}}` go to Service `player-ui-next` (port `80`), all other requests for `{{PREVIEW_PATH}}` go to `player-ui` (port `80`)

Do not modify or delete the Ingress.

## Hints

- Translate each Ingress path into a rule: `pathType: Prefix` becomes `path.type: PathPrefix`, the Service backend becomes a `backendRef` with `name` and `port`, the Ingress `host` goes into `spec.hostnames`.
- Inside one entry of `matches`, all conditions must be true (AND); separate entries of `matches` are alternatives (OR). A header condition that is its own list entry matches requests on every path.
- Use two rules for `{{PREVIEW_PATH}}`: one with path and header in the same match, one with only the path. Among rules that match a request, the one with more header matches wins, whatever the order of the rules.

## Solution

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: media-route
  namespace: media-hub
spec:
  parentRefs:
  - name: media-gateway
  hostnames:
  - media.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /watch
    backendRefs:
    - name: player-ui
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: media-api
      port: 8080
  - matches:
    - path:
        type: PathPrefix
        value: {{PREVIEW_PATH}}
      headers:                      # same list entry as path: path AND header
      - type: Exact
        name: {{HEADER}}
        value: {{HEADER_VALUE}}
    backendRefs:
    - name: player-ui-next
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: {{PREVIEW_PATH}}
    backendRefs:
    - name: player-ui
      port: 80
```

```bash
k config use-context {{CONTEXT}}
k apply -f media-route.yaml
k -n media-hub describe httproute media-route
```

A `- headers:` entry of its own under `matches` would be an OR: every request with the header would go to `player-ui-next`, also on `/watch` and `/api`. When several rules match, the Gateway API picks by precedence (an Exact path, then the longest prefix, then the method, then the most header matches), not by order, so the header rule wins for `{{PREVIEW_PATH}}` even if it comes last. `ingress2gateway` (kubernetes-sigs) can convert Ingress manifests, but it is not available in the exam. No controller implements the GatewayClass of this lab, so only the HTTPRoute is graded: the check evaluates its rules for sample requests.
