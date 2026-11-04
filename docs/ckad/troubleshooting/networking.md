# Networking Debug Scenarios

Focus on the 3 most common networking failures in CKAD exam.

---

## Scenario 1: Service Selector Mismatch (Endpoints = 0)

**Problem:** Service created, pods running, but service.endpoints empty.

```bash
# Endpoints show: <none>
kubectl get endpoints myservice

# Root cause: service.selector doesn't match pod.labels
```

**Debug & Fix:**
```bash
# 1. Check service selector
kubectl get svc myservice -o jsonpath='{.spec.selector}'
# Output: {"app":"myapp","tier":"backend"}

# 2. Check pod labels
kubectl get pod --show-labels
# NAME    LABELS
# pod-1   app=myapp,tier=backend  ✓
# pod-2   app=web,tier=database   ✗

# 3. Fix: Edit service to match pod labels
kubectl edit svc myservice
# Or recreate:
kubectl delete svc myservice
kubectl expose deployment myapp --name=myservice

# 4. Verify endpoints now non-empty
kubectl get endpoints myservice
```

---

## Scenario 2: Ingress 503 (Backend Service Broken)

**Problem:** Ingress created, but external requests get 503 Service Unavailable.

```bash
# External: curl ingress-ip
# Result: 503 Service Unavailable
```

**Checklist:**
```bash
# 1. Ingress exists and has address?
kubectl get ingress
# Should show: ADDRESS column populated

# 2. Service referenced in ingress exists?
kubectl get svc
# Service must exist

# 3. Service has endpoints?
kubectl get endpoints <service-name>
# Should NOT be empty

# 4. Service port matches ingress backend port?
kubectl get svc -o yaml | grep -A 3 "ports:"
# Service port: 80 (for example)
# Ingress backend.service.port should be: 80 (NOT targetPort)

# 5. Pod labels match service selector?
kubectl get pod --show-labels
kubectl get svc <name> -o jsonpath='{.spec.selector}'
# Must match exactly

# Fix priority:
# IF endpoints empty: Fix selector match
# IF service port wrong in ingress: Fix ingress backend.service.port
# IF pod labels wrong: Fix pod labels or redesign service
```

---

## Scenario 3: NetworkPolicy Blocking Valid Traffic

**Problem:** NetworkPolicy created, but traffic incorrectly blocked.

```bash
# Test: kubectl exec <pod1> -- curl <pod2>:80
# Result: Connection refused or timeout
# But it should work!
```

**Debug:**
```bash
# 1. Check if NetworkPolicy exists
kubectl get networkpolicy

# 2. Which policies affect my pods?
kubectl get networkpolicy -o wide

# 3. Check policy rules
kubectl get networkpolicy <name> -o yaml

# Common mistakes:
# - podSelector empty {} means ALL pods (might not intend that)
# - ingress rule missing (everything denied by default)
# - label selector wrong (policy doesn't match any pods)
# - port number mismatch (policy allows 80 but pods listen 8080)

# Fix:
# 1. Check pod labels:
kubectl get pod --show-labels

# 2. Edit policy to include correct labels:
kubectl edit networkpolicy <name>

# 3. Add/fix ingress rule:
ingress:
  - from:
      - podSelector:
          matchLabels:
            allowed: "yes"
    ports:
      - protocol: TCP
        port: 80

# 4. Test again:
kubectl exec <pod1> -- curl <pod2>:80
```

---

## Scenario 4: Ingress Path Routing Fails

**Problem:** Ingress created with multiple paths, but traffic not routed correctly.

```bash
# curl ingress-ip/api/v1/users → Gets /static instead
# Request: /api/v1/users
# Response: 404 (app looking for /static/users)
```

**Scenario Example:**
```yaml
# Ingress with path-based routing
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 8080
```

**Fix:**
```bash
# May need rewrite rule (NGINX annotation):
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 8080

# Rewrite: /api/users → /users (app receives correct path)
```

---

## Quick Networking Checklist

Before declaring "networking broken":

- [ ] Service exists: `kubectl get svc`
- [ ] Service has endpoints: `kubectl get endpoints` (not empty)
- [ ] Pod labels match service selector: `kubectl get pod --show-labels`
- [ ] Port chain correct: container port → service port → ingress backend port
- [ ] Ingress backend service name spelled correctly
- [ ] NetworkPolicy doesn't block (check pod labels in policy)
- [ ] Test from pod: `kubectl exec <pod> -- curl <service>:<port>`

