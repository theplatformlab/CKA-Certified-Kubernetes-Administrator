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

1. Create 3 namespaces: `frontend`, `backend`, `database`
2. Deploy apps:
   - Frontend (nginx): labels `tier=frontend`
   - Backend (busybox): labels `tier=backend`
   - Database (redis): labels `tier=database`
3. Create NetworkPolicies:
   - Allow frontend → backend (only port 8080)
   - Allow backend → database (only port 6379)
   - Deny all other traffic initially (prefer-deny ingress)
   - Allow DNS egress (UDP 53) to kube-dns for all pods
4. **Explicitly test connectivity** to confirm policies are enforced:
   - Frontend CAN reach backend on 8080 only
   - Frontend CANNOT reach database
   - Backend CAN reach database on 6379
   - Backend CANNOT reach frontend
5. Verify DNS still works from all namespaces (tests egress rules)
6. If policies don't enforce, verify CNI supports NetworkPolicy

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
- For cross-namespace policies: use `namespaceSelector` with namespace labels (label namespaces first!)
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
# Pods are running in correct namespaces
k get pods -A

# NetworkPolicies exist
k get networkpolicies -A

# From frontend, test connectivity
k exec -it <frontend-pod> -n frontend -- curl http://backend.<backend>.svc.cluster.local:8080
# Should succeed

# From frontend, try database (should fail)
k exec -it <frontend-pod> -n frontend -- curl http://database.<database>.svc.cluster.local:6379
# Should timeout/fail

# Test DNS works
k exec -it <any-pod> -- nslookup kubernetes.default
# Should succeed
```

## Cleanup

```bash
k delete ns frontend backend database
```

<details>
<summary>Solution</summary>

```bash
# Create namespaces (create ns takes one name only)
k create ns frontend
k create ns backend
k create ns database

# Label namespaces for cross-ns selection
k label ns frontend name=frontend
k label ns backend name=backend
k label ns database name=database

# Deploy frontend (nginx listens on 80)
k run frontend-web -n frontend --image=nginx:1.27 --labels=tier=frontend

# Deploy backend (busybox httpd listens on 8080; plain sleep listens on nothing -> "refused")
k run backend-api -n backend --image=busybox:1.36 --labels=tier=backend --command -- httpd -f -p 8080

# Deploy database (redis listens on 6379)
k run database-redis -n database --image=redis:7 --labels=tier=database

# Create services
k expose pod frontend-web -n frontend --port=80 --type=ClusterIP
k expose pod backend-api -n backend --port=8080 --type=ClusterIP
k expose pod database-redis -n database --port=6379 --type=ClusterIP

# Allow frontend → backend
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
          name: frontend
    ports:
    - protocol: TCP
      port: 8080
EOF

# Allow backend → database
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
          name: backend
    ports:
    - protocol: TCP
      port: 6379
EOF

# Default-deny ingress for frontend (backend and database are already
# ingress-isolated by the policies above)
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: frontend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

# Egress per namespace: DNS for all + the one app port each source needs.
# A podSelector: {} Egress policy isolates every pod's egress, so a
# DNS-only policy alone would block frontend->backend and backend->database.

# Frontend egress: DNS + backend:8080
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: frontend
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
  - to:
    - namespaceSelector:
        matchLabels:
          name: backend
    ports:
    - protocol: TCP
      port: 8080
EOF

# Backend egress: DNS + database:6379
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
  - to:
    - namespaceSelector:
        matchLabels:
          name: database
    ports:
    - protocol: TCP
      port: 6379
EOF

# Database egress: DNS only
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: database
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
EOF

# Test connectivity (refused in 0 ms = nothing listening; hang/timeout = policy drop)
# Frontend → Backend (should work; 404 is fine, it means connected)
k exec frontend-web -n frontend -- curl -s -m 2 -o /dev/null -w '%{http_code}\n' http://backend-api.backend:8080

# Frontend → Database (should time out)
k exec frontend-web -n frontend -- curl -m 2 http://database-redis.database:6379

# Backend → Database (should print +PONG)
k exec backend-api -n backend -- sh -c 'echo PING | nc -w 2 database-redis.database 6379'

# Backend → Frontend (should time out)
k exec backend-api -n backend -- wget -qO- -T 2 http://frontend-web.frontend
```

</details>
