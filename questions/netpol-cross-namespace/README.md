# NetworkPolicies across namespaces, ingress and egress

**Context:** `kubectl config use-context {{CONTEXT}}`

An application is spread over three namespaces. None of them has NetworkPolicies yet.

| Namespace | Deployment / Service | Pod label | Ports |
|---|---|---|---|
| `frontend` | `frontend` | `tier=frontend` | 80 |
| `backend` | `backend` | `tier=backend` | {{API_PORT}} (API), 9090 (admin) |
| `database` | `database` | `tier=database` | 6379 |

Create NetworkPolicies so that:

1. All ingress **and** egress traffic of all pods in `frontend`, `backend` and `database` is denied by default.
2. Pods with `tier=frontend` in `frontend` can connect to pods with `tier=backend` in `backend` on TCP port `{{API_PORT}}` only.
3. Pods with `tier=backend` in `backend` can connect to pods with `tier=database` in `database` on TCP port `6379` only.
4. All pods in the three namespaces can resolve DNS names through the cluster DNS (pods with `k8s-app=kube-dns` in `kube-system`, UDP and TCP port `53`).

No other traffic may be allowed. In particular, pods with `tier=frontend` in other namespaces must not reach the backend.

## Hints

- With egress denied too, an allowed connection needs two rules: egress on the source pods and ingress on the destination pods.
- Every namespace has the label `kubernetes.io/metadata.name: <name>`; use it in a `namespaceSelector`.
- `namespaceSelector` and `podSelector` in the **same** `from`/`to` entry mean "pods with this label in that namespace". As two separate entries they are OR-ed.

## Solution

```bash
for ns in frontend backend database; do
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: $ns
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF
done
```

```yaml
# frontend -> backend: egress on the source ...
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-backend
  namespace: frontend
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: backend
      podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: {{API_PORT}}
---
# ... and ingress on the destination
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
      podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: {{API_PORT}}
---
# backend -> database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-database
  namespace: backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
      podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-database
  namespace: database
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: backend
      podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 6379
```

Test from a pod with the right labels:

```bash
k -n frontend run t --rm -it --image=busybox:1.37 --labels=tier=frontend --restart=Never -- \
  wget -qO- -T 3 http://backend.backend:{{API_PORT}}
```

## Pitfalls

- A correct ingress rule on the backend can still leave traffic blocked: the frontend's default-deny egress dropped it at the source. Both sides must allow it.
- Writing app rules before the DNS rule makes every test by Service name fail, which looks like a broken app rule. Allow DNS first.
- A blocked connection times out; "connection refused" means the policy let it through and nothing listens on that port.
