# NetworkPolicies for a three-tier app

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `shop` runs three Deployments, `frontend`, `backend` and `database`, with pod labels `tier=frontend`, `tier=backend` and `tier=database`. Each tier has a Service with the same name. Currently all traffic is allowed.

Create NetworkPolicies in namespace `shop` so that:

1. Pods with `tier=frontend` accept ingress on TCP port `80` from anywhere, including other namespaces.
2. Pods with `tier=backend` accept ingress only from `tier=frontend` pods in `shop`, on TCP port `3000`.
3. Pods with `tier=database` accept ingress only from `tier=backend` pods in `shop`, on TCP port `5432`.
4. All other ingress traffic to pods in `shop` is denied. Do not restrict egress.

## Hints

- Start with a default-deny ingress policy (`podSelector: {}`, `policyTypes: [Ingress]`) and open what's needed per tier.
- An ingress rule with `ports` but no `from` allows that port from everywhere.
- A `podSelector` inside `from` (without namespaceSelector) only matches pods in the policy's own namespace.

## Solution

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: shop
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes: [Ingress]
  ingress:
  - ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 3000
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
```

- An ingress rule with `ports` but no `from` allows that port from everywhere, which is what the frontend needs.
- A `podSelector` inside `from` without a `namespaceSelector` only matches pods in the policy's own namespace.
- Only ingress is restricted, so DNS (egress) keeps working.

Test it:

```bash
k -n shop run t --rm -it --image=busybox:1.37 --labels=tier=frontend --restart=Never -- wget -qO- -T 3 backend:3000
```
