# NetworkPolicy Pattern (Allow/Deny)

**Curriculum domain:** Services and Networking (20%)

---

## Core Principle

**Default: Everything is allowed.** NetworkPolicy = explicit allow. Anything NOT explicitly allowed = DENIED.

---

## Problem Scenario

> Create a NetworkPolicy in namespace 'prod' that:
> - Allows traffic FROM frontend pods (label: tier=frontend) TO backend pods (label: tier=backend) on port 8080
> - Denies all other traffic

---

## Exact YAML Template

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow
  namespace: prod
spec:
  # Select which pods this policy protects
  podSelector:
    matchLabels:
      tier: backend
  
  # Define policy type
  policyTypes:
    - Ingress  # Control incoming traffic

  # Rules: explicit allow
  ingress:
    - from:
        # Allow FROM pods with this label
        - podSelector:
            matchLabels:
              tier: frontend
      ports:
        - protocol: TCP
          port: 8080
```

**Effect:** Only frontend pods can reach backend on port 8080. Everything else blocked.

---

## Quick Creation (Command Line)

```bash
# Create namespace
kubectl create namespace prod

# Create backend pod (target)
kubectl run backend --image=nginx --labels=tier=backend -n prod
kubectl expose pod backend --port=8080 --target-port=80 -n prod

# Create frontend pod (source)
kubectl run frontend --image=nginx --labels=tier=frontend -n prod

# Apply NetworkPolicy
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow
  namespace: prod
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: frontend
      ports:
        - protocol: TCP
          port: 8080
EOF
```

---

## Verification

```bash
# 1. Frontend CAN reach backend
kubectl exec -it frontend -n prod -- wget -O- http://backend:8080
# Should work ✓

# 2. Other pods CANNOT reach backend
kubectl run other --image=nginx -n prod
kubectl exec -it other -n prod -- wget -O- http://backend:8080 --timeout=2
# Should timeout ✗
```

---

## Common Exam Variations

### 1. Allow Multiple Sources
```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            tier: frontend
      - podSelector:
          matchLabels:
            tier: cache  # ALSO allow caches
    ports:
      - protocol: TCP
        port: 8080
```

### 2. Allow Traffic from Different Namespace
```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring  # Pods from monitoring NS
    ports:
      - protocol: TCP
        port: 9090
```

### 3. Allow Egress (Outgoing) Only
```yaml
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: db
      ports:
        - protocol: TCP
          port: 5432
```

### 4. Deny All (Firewall Everything)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: prod
spec:
  podSelector: {}  # Select ALL pods
  policyTypes:
    - Ingress
  ingress: []  # No allow rules = everything denied
```

---

## Debugging NetworkPolicy Issues

```bash
# Check if NetworkPolicy exists
kubectl get networkpolicy -n prod

# View full policy
kubectl get networkpolicy backend-allow -n prod -o yaml

# Check pod labels (labels MUST match exactly)
kubectl get pod -n prod --show-labels

# Common mistake: pod selector empty (affects all pods!)
# kubectl get po backend-allow -o yaml | grep -A 3 "podSelector:"
# Should show labels, not empty {}

# Test with netcat (if available)
kubectl exec frontend -n prod -- nc -zv backend 8080
```

---

## Exam Shortcut

1. **Read the requirement carefully** — "Allow X to Y" = ingress rule on Y
2. **List matching pods** → Check labels match requirement
3. **Write NetworkPolicy** → Copy template, fill in labels/ports
4. **Test both directions** → One works, other fails = correct
5. **Check selector** → Most common mistake: empty podSelector `{}`

---

## Time Pressure Tips

- Don't create 5 separate NetworkPolicies → One policy with multiple `from` blocks is faster
- Verify with `kubectl exec ... wget` (instant feedback vs waiting for probe)
- Copy-paste template from exam notes, fill in blanks only
