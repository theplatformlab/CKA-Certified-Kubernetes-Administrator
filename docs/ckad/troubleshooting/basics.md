# Basics — Common Pitfalls & Namespace Mistakes

Foundational knowledge that trips up exam candidates.

---

## Namespace Fundamentals

### Rule 1: Kubernetes Resources are Namespace-Scoped

- Pods, Services, Deployments → tied to namespace
- Nodes, ClusterRoles, PersistentVolumes → cluster-wide

### Rule 2: Default Namespace is 'default'

```bash
# No -n flag = default namespace
kubectl run app --image=nginx
# Creates in 'default'

# To use different namespace:
kubectl run app --image=nginx -n prod
```

### Rule 3: Services Only See Pods in Same Namespace

```bash
# Service in 'default' can ONLY connect to pods in 'default'
# Can't reach pods in 'prod' namespace

# Access across namespaces:
# Service DNS: <service-name>.<namespace>.svc.cluster.local
# Example: api-svc.prod.svc.cluster.local
```

---

## Label and Selector Rules

### Rule 4: Labels Must Match Exactly (Case-Sensitive)

```bash
# Pod has label:
labels:
  app: myapp

# Service selector MUST be:
selector:
  app: myapp

# NOT: app: myApp (capital A fails!)
# NOT: app: my-app (dash fails!)
```

### Rule 5: Empty Selector Means "Match Everything"

```yaml
# This selects ALL pods in namespace:
selector: {}

# This selects pods with 'app: web':
selector:
  app: web

# This selects pods with BOTH labels:
selector:
  app: web
  tier: frontend
```

---

## Context and Kubeconfig Rules

### Rule 6: Context Determines Cluster + Namespace

```bash
# Switch cluster
kubectl config use-context my-cluster

# Switch namespace in current cluster
kubectl config set-context --current --namespace=prod

# Check current
kubectl config current-context
# Also shows: kubectl get ns (if current context set)
```

---

## Port Mapping Rules

### Rule 7: Container Port ≠ Service Port ≠ Ingress Port

```yaml
# Pod container listens on:
containers:
  - ports:
    - containerPort: 8080

# Service definition:
ports:
  - port: 80           # External service port
    targetPort: 8080   # Maps to container port

# Ingress backend:
backend:
  service:
    port:
      number: 80       # Must match service.port (NOT targetPort)
```

---

## Probes and Restarts

### Rule 8: Liveness Probe Killing Healthy Pods = Bad

```yaml
# WRONG: App takes 30s to start, probe starts at 5s
livenessProbe:
  tcpSocket:
    port: 8080
  initialDelaySeconds: 5  # TOO SHORT!

# RESULT: Pod restarted 3× before app even starts = CrashLoopBackOff

# FIX: Match app startup time
livenessProbe:
  tcpSocket:
    port: 8080
  initialDelaySeconds: 30  # Wait long enough
```

### Rule 9: Readiness Probe Prevents Traffic (Doesn't Restart)

```yaml
# If readiness probe fails:
# - Pod stays running
# - Service removes pod from endpoints
# - No traffic sent to this pod

# If liveness probe fails:
# - Kubelet stops pod and restarts it
```

---

## Status vs. Events Debugging

### Rule 10: Check Both Status AND Events

```bash
# See pod status
kubectl get pod myapp
# Output: STATUS=CrashLoopBackOff

# See WHY:
kubectl describe pod myapp | grep -A 5 "Events:"
# Shows: "ImagePullBackOff" or "Liveness probe failed"

# See container output:
kubectl logs myapp
# Shows actual error message
```

---

## Permanent Checklist (Memorize This)

Before EVERY question:

1. **What namespace am I in?**  
   `kubectl config get-contexts`

2. **Do all my resources have matching labels/selectors?**  
   `kubectl get pod --show-labels`  
   `kubectl get svc -o jsonpath='{.spec.selector}'`

3. **After creating, verify it worked:**  
   `kubectl get <resource>`  
   `kubectl describe <resource>`  
   `kubectl logs <pod>` (if applicable)

4. **Ports correct end-to-end?**
   - Container listens on X
   - Service targetPort: X, port: Y  
   - Ingress backend.service.port: Y

5. **Permissions correct?**  
   `kubectl auth can-i [verb] [resource] --as=<serviceaccount>`

---

## One-Liner Testing After Each Creation

```bash
# After creating any resource, run:
kubectl get <resource> -o wide -n <namespace>

# If deployment:
kubectl get deployment myapp -o wide && kubectl get pod -l app=myapp -o wide

# If service:
kubectl get svc mysvc -o wide && kubectl get endpoints mysvc

# If pod:
kubectl get pod mypod -o wide && kubectl logs mypod
```

This catches 90% of configuration errors immediately.

