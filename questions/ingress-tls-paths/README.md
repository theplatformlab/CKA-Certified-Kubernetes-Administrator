# Ingress with TLS

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `api`, a Service `api` listens on port `8080`. The TLS Secret `api-tls-cert` and the IngressClass `nginx` already exist.

Create an Ingress named `api-ingress` in namespace `api`:

- IngressClass `nginx`
- TLS for host `api.example.com` using Secret `api-tls-cert`
- host `api.example.com` with two paths, both going to Service `api` on port `8080`:
  - `/api`, path type `Prefix`
  - `/health`, path type `Exact`

## Hints

- `kubectl create ingress` supports `--class`, several `--rule` flags and `tls=<secret>` inside a rule.
- In `--rule`, a path ending in `*` becomes pathType Prefix; without `*` it's Exact.
- The tls section needs both `hosts` and `secretName`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n api create ingress api-ingress --class=nginx \
  --rule="api.example.com/api*=api:8080,tls=api-tls-cert" \
  --rule="api.example.com/health=api:8080" $do > ing.yaml
```

Check the result: `/api*` becomes `pathType: Prefix` and `/health` becomes `Exact`.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: api
spec:
  ingressClassName: nginx
  tls:
  - hosts: [api.example.com]
    secretName: api-tls-cert
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 8080
      - path: /health
        pathType: Exact
        backend:
          service:
            name: api
            port:
              number: 8080
```

No ingress controller runs in the exam cluster, so only the resource is graded.
