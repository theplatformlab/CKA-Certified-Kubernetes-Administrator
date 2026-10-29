# Exercise 28 — Complex NetworkPolicy (Multi-Namespace, Traffic Control)

> Related: [NetworkPolicy skeleton](../../skeletons/networkpolicy.yaml) | [README — Networking](../../README.md#domain-5--services--networking-13) | **Updated May 2026**

Create multi-namespace NetworkPolicies with ingress/egress rules with careful label matching and debugging. Understand that NetworkPolicy enforcement depends on the CNI (Container Network Interface) plugin your cluster uses — not all CNIs enforce all policy rules equally.

## Conventions

NetworkPolicy troubleshooting involves multiple trap levels:

- **Primary Trap:** Ingress rules on destination pod but egress missing on source pod — traffic blocked at source
- **Secondary Trap (Gotcha 1):** Label selector typo or case mismatch — policies silently don't apply
- **Secondary Trap (Gotcha 2):** CNI doesn't support NetworkPolicy enforcement (e.g., flannel) — policies exist but don't block
- **Validation Criteria:** Your implementation is correct if:
  - Allowed traffic flows with exact port match
  - Disallowed traffic times out (not rejected, but blocked passively)
  - DNS works (explicit egress UDP 53 rule required)
  - `kubectl describe networkpolicy` shows correct selector labels
  - `k get pods --show-labels` confirms pod labels match policy selectors
- **Scoring:** Full credit for end-to-end connectivity working + all 3 namespaces isolated correctly. Partial for policies created but not tested.

## Important: CNI-Aware Testing

NetworkPolicy resources exist across all Kubernetes clusters, but whether they're *enforced* depends on your CNI:

- **Enforcing CNIs**: Calico, Cilium, Weave, Kube-router
- **Non-enforcing CNIs**: flannel, kubenet (pass-through)

If your CNI doesn't enforce policies, the NetworkPolicy objects exist but traffic flows freely. Exam clusters use enforcing CNIs (usually Calico). For testing locally, verify your CNI supports NetworkPolicy before debugging.

## Tasks

The namespaces `frontend`, `backend` and `database` exist, without any NetworkPolicies yet (`./scripts/lab.sh setup 28` creates them), and run:

| Namespace | Deployment / Service | Image | Pod label | Ports |
|-----------|----------------------|-------|-----------|-------|
| `frontend` | `frontend` | `nginx:1.28` | `tier=frontend` | 80 |
| `backend` | `backend` | `busybox:1.37` (httpd) | `tier=backend` | 8080 (API), 9090 (admin) |
| `database` | `database` | `redis:8.8-alpine` | `tier=database` | 6379 |

1. Inspect the apps: `k get pods,svc -n <ns> --show-labels` in all three namespaces
2. Create NetworkPolicies so that:
   - Everything in `frontend`, `backend` and `database` is denied by default (ingress **and** egress)
   - Pods with `tier=frontend` in namespace `frontend` can reach pods with `tier=backend` in namespace `backend` on TCP 8080 only
   - Pods with `tier=backend` in namespace `backend` can reach pods with `tier=database` in namespace `database` on TCP 6379 only
   - All pods in the three namespaces can resolve DNS (UDP and TCP 53 to kube-dns in `kube-system`)
3. **Explicitly test connectivity** to confirm policies are enforced:
   - Frontend CAN reach backend on 8080, but NOT on 9090
   - Frontend CANNOT reach database
   - Backend CAN reach database on 6379
   - Backend CANNOT reach frontend
   - A `tier=frontend` pod in another namespace (e.g. `default`) CANNOT reach backend
4. Verify DNS still works from all three namespaces (tests egress rules)
5. If policies don't enforce, verify CNI supports NetworkPolicy (the lab cluster's kindnet does)

Validate with `./scripts/lab.sh check 28` — it runs throwaway pods with the tier labels in each namespace and tests the traffic above.

## Key Learning

- NetworkPolicies are pod label selectors, not namespace selectors alone
- Ingress rules applied to target pods
- Egress rules applied to source pods
- Must explicitly allow DNS egress or service discovery breaks
- Debugging: use `k describe pod` and check labels carefully
- Exam tests label matching precision

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- **Check CNI enforcement first:** `k get pods -n kube-system | grep -i cni` or `kubectl describe node` to see CNI plugin
- For cross-namespace policies: use `namespaceSelector` with namespace labels (every namespace has `kubernetes.io/metadata.name: <name>`)
- DNS rule: egress with `to: []` and `ports: [{protocol: UDP, port: 53}]` (empty `to` means all destinations)
- Test connectivity with **explicit port**: `k exec <pod> -- curl http://service.namespace.svc.cluster.local:8080`
- Debug: `k describe networkpolicy <name>` shows selectors AND rules clearly
- **Order matters:** ingress applied to destination pod, egress to source pod. Both must allow for traffic to flow.
- **Timeouts mean denial:** If `curl` hangs with no response, the policy is likely dropping packets (good sign policies work!)
- **CNI not enforcing?** Policies may exist but not be enforced. Verify with `k get networkpolicies` and check node's CNI plugin.

</details>

## What tripped me up

> **Bidirectional Rule Trap (Most Common Exam Failure):** Created perfect ingress rules on backend, but traffic was still blocked. Forgotten step: egress rules on the SOURCE pod (frontend). NetworkPolicy enforces BOTH ingress (destination) and egress (source). If frontend has default-deny egress without explicit allowlist, traffic never leaves. BOTH sides must say yes. Common test failure: "I wrote the policy correctly but traffic didn't flow."
>
> **DNS Discovery Broken by Network Policy:** All pods suddenly can't resolve service names (`nslookup kubernetes.default` times out). Usually because: I wrote app traffic rules but forgot explicit DNS egress. DNS runs on `kube-dns` service (usually IP 10.96.0.10) port UDP 53. Every namespace getting egress restriction needs an explicit "allow-dns-egress" rule. This breaks service discovery and confuses exam candidates.
>
> **Label Matching Case Sensitivity (Silent Failure):** Policy says `tier: backend` but pod is labeled `tier: Backend` (capital B). Label matching is CASE-SENSITIVE and fails silently with no error message. Traffic just blocks with no indication why. Fix: `kubectl get pods --show-labels` to verify exact label values, then compare with policy `.spec.podSelector.matchLabels`.
>
> **CNI Enforcement Doesn't Apply Universally:** NetworkPolicy objects exist on flannel clusters but traffic flows freely (flannel doesn't enforce). CKA exam uses Calico (which enforces), but self-testing might use non-enforcing CNI. Check: `k get pods -n kube-system | grep -i cni` shows which plugin. Calico, Cilium, Weave ENFORCE. Flannel, kubenet DO NOT. If policies don't work, check CNI first.
>
> **May 2026 Gotcha (Empty Selectors):** In k8s 1.35, an empty `podSelector: {}` in ingress means "all pods in this namespace" — it's a blanket allow. An empty `namespaceSelector: {}` means "all namespaces." Empty selectors are powerful but often misunderstood. Verify you're using them intentionally, not by accident.
>
> **Port Range Behavior (endPort Quirks):** Policy allows `port: 8080, endPort: 8090` (range). But on some CNIs (Calico specifically), `endPort` behavior changed between k8s 1.33 and 1.35. Test the upper bound: traffic on 8090 might be allowed or blocked depending on CNI version. Always test specific ports, not assume range behavior.
>
> **Traffic TIMEOUT vs REFUSED:** If traffic timeouts (hangs), policy is blocking it (good, working). If you get connection refused (RST packet), the pod isn't listening or there's another issue. Don't mistake connection refused for policy not working. Use `k exec <pod> -- netstat -tulnp` to verify target pod is actually listening on the port.

## Verify

```bash
./scripts/lab.sh check 28
```

Manual checks:

```bash
# Pods and labels
k get pods -n frontend --show-labels
k get pods -n backend --show-labels
k get pods -n database --show-labels

# NetworkPolicies exist
k get networkpolicies -n frontend
k get networkpolicies -n backend
k get networkpolicies -n database

# Test as a frontend pod (the policies select pods by label)
k -n frontend run t --image=busybox:1.37 --labels=tier=frontend --rm -it --restart=Never -- sh
#   wget -qO- -T 3 http://backend.backend.svc.cluster.local:8080      # backend   (allowed)
#   wget -qO- -T 3 http://backend.backend.svc.cluster.local:9090      # times out (blocked)
#   echo PING | nc -w 3 database.database.svc.cluster.local 6379     # no PONG   (blocked)
#   nslookup kubernetes.default                                       # resolves

# Test as a backend pod
k -n backend run t --image=busybox:1.37 --labels=tier=backend --rm -it --restart=Never -- sh
#   echo PING | nc -w 3 database.database.svc.cluster.local 6379     # +PONG     (allowed)
#   wget -qO- -T 3 http://frontend.frontend.svc.cluster.local         # times out (blocked)
```

## Cleanup

```bash
./scripts/lab.sh cleanup 28
```

<details>
<summary>Solution</summary>

Every namespace gets a default deny for both directions plus a DNS allowance. Then each allowed flow needs **two** rules: egress on the source and ingress on the destination. Namespaces carry the automatic label `kubernetes.io/metadata.name`, so there is no need to label them yourself. `namespaceSelector` and `podSelector` in the **same** `from`/`to` entry mean "pods with this label in that namespace".

```bash
# Baseline for every namespace: deny all traffic, then allow DNS to kube-dns
for ns in frontend backend database; do
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
  - Egress
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

# frontend -> backend:8080 (egress on the source)
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-backend
  namespace: frontend
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Egress
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
      port: 8080
EOF

# backend: ingress from frontend on 8080, egress to database on 6379
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
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
      port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-database
  namespace: backend
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Egress
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
EOF

# database: ingress from backend on 6379
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-database
  namespace: database
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
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
EOF

# Verify
k get networkpolicies -n frontend
k get networkpolicies -n backend
k get networkpolicies -n database
./scripts/lab.sh check 28
```

</details>
