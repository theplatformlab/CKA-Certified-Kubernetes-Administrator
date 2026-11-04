# Service Selector Mismatch Pattern

**Curriculum domain:** Services and Networking (20%); the same check helps whenever a task's traffic doesn't arrive

---

## Problem Scenario

> Service created but shows 0 endpoints. Pods can't communicate. Debug.

---

## Root Cause

Service selector doesn't match pod labels. Always case-sensitive, no fuzzy matching.

---

## Diagnosis

```bash
# 1. Check service selector
kubectl get svc myservice -o jsonpath='{.spec.selector}'
# Output: {"app":"myapp","tier":"backend"}

# 2. Check pod labels
kubectl get pod --show-labels
# NAME          READY  STATUS  RESTARTS  LABELS
# pod-xyz       1/1    Running 0         app=myapp,tier=backend ✓
# pod-abc       1/1    Running 0         app=otherapp ✗

# 3. Check endpoints (should match pods above)
kubectl get endpoints myservice
# NAME        ENDPOINTS        AGE
# myservice   10.0.0.5:8080   2m  (IP from pod-xyz)

# If endpoints empty = selector mismatch!
```

---

## Quick Fix

```bash
# Option 1: Edit service and fix selector
kubectl edit svc myservice
# Change: selector: app: [CORRECT-LABEL]

# Option 2: Recreate service with correct selector
kubectl delete svc myservice
kubectl create service clusterip myservice \
  --tcp=80:8080 \
  --selector app=myapp,tier=backend

# Option 3: Update pod labels to match
kubectl label pod pod-xyz app=myapp --overwrite
```

---

## Verification

```bash
# After fix, endpoints should be non-empty:
kubectl get endpoints myservice
# NAME        ENDPOINTS
# myservice   10.0.0.5:8080,10.0.0.6:8080

# Test connectivity
kubectl run test-pod --image=nginx -it -- curl http://myservice:80
```

---

## Common Mistakes

| Mistake | Why It Fails |
|---------|-------------|
| Selector: `app: nginx` but pod label: `app: nginx-server` | Case-sensitive, no fuzzy match; exact string required |
| Service in NS1, pods in NS2 | Service only sees pods in same namespace |
| Label has quotes `"app"` but no quotes in selector | YAML parser difference |
| Three pods, only two in endpoints | Third pod label doesn't match |
| Edited pod label but service doesn't reflect | Delete service, recreate (labels are snapshot) |

---

## Real Exam Variation

```bash
# Given: Service created but 0 endpoints
# You must:
# 1. kubectl get svc
# 2. Check selector
# 3. kubectl get pod --show-labels
# 4. Find mismatch (e.g., app=web but selector wants app=website)
# 5. Fix: kubectl edit svc OR kubectl label pod
# 6. Verify: kubectl get endpoints shows pods
```

Exam will likely give you service + pods; you find the label mismatch and fix.

---

## One-Minute Drill

```bash
# Copy this flow:
kubectl get svc -o wide
# Read selector column
kubectl get pod --show-labels
# Compare labels to selector
kubectl get endpoints
# Should show IPs matching pod labels
```

Practice this 5× before exam.
