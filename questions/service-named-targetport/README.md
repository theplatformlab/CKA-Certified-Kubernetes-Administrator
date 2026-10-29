# Service without endpoints

**Context:** `kubectl config use-context {{CONTEXT}}`

Clients get no answer from `http://catalog-api.catalog` (port `80`). The pods of Deployment `catalog-api` in namespace `catalog` are `Running` and `Ready`.

Find the cause and fix it so that the Service `catalog-api` forwards port `80` to both pods. Do not modify the Deployment, and keep the Service port `80`.

## Hints

- `k -n catalog describe svc catalog-api` and `k -n catalog get endpointslices -o yaml`: which pods and which port are listed?
- The selector matches. Look at the Service's `targetPort` and at the container's `ports` section.
- A named `targetPort` must match the `name` of a container port. The container port is called `api-http`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n catalog get svc,endpointslices,pods -o wide --show-labels
k -n catalog get svc catalog-api -o jsonpath='{.spec.ports}'                          # targetPort: http
k -n catalog get deploy catalog-api -o jsonpath='{.spec.template.spec.containers[0].ports}'  # name: api-http, 8080

k -n catalog patch svc catalog-api --type=json \
  -p '[{"op":"replace","path":"/spec/ports/0/targetPort","value":"api-http"}]'
# or k -n catalog edit svc catalog-api  ->  targetPort: api-http   (8080 works too)

k -n catalog get endpointslices                                  # 2 endpoints, port 8080
k run t --rm -it --image=busybox:1.37 --restart=Never -- wget -qO- catalog-api.catalog
```

The selector is correct, so the EndpointSlice lists both pods, but with `ports: null`: a named `targetPort` that no container port carries can't be resolved to a number, and kube-proxy has nothing to forward to. `k describe svc` even shows the pod IPs under `Endpoints:`, but without a port, so connections fail although the pods are Ready.
