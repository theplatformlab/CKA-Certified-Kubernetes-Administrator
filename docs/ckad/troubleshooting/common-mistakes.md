# Common Mistakes — Learn From Them Before the Exam

These errors cost exam candidates the most time.

---

## Namespace Mistakes

### ❌ MISTAKE: Service in NS1, Pods in NS2

```bash
# Created service in 'prod'
kubectl create svc clusterip myservice --port=80 -n prod

# But pods running in 'default'
kubectl get pod (shows nothing in prod)

# Service shows 0 endpoints!
```

**Fix:** Services only see pods in THE SAME namespace.

```bash
# Ensure deployment and service in same namespace:
kubectl create deployment app --image=nginx -n prod
kubectl get pod -n prod  # Should show pods
kubectl expose deployment app --name=myservice -n prod
```

---

### ❌ MISTAKE: Forgot to Set Namespace in kubectl Command

```bash
$ kubectl get pod
# Shows pods in 'default' NS

$ kubectl apply -f deployment.yaml
# YAML has namespace: prod inside
# But kubectl applies to current NS!

# Pod created twice if not careful
```

**Fix:** Always specify `-n <namespace>` OR include namespace in YAML.

```bash
# BE EXPLICIT:
kubectl apply -f deployment.yaml -n prod

# OR in YAML:
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: prod  # Specify here
  name: app
```

---

## Label/Selector Mistakes

### ❌ MISTAKE: Service Selector Doesn't Match Pod Label

```bash
# Service selector:
selector:
  app: web

# But pods have:
labels:
  app: webapp  # NOT "web"!

# Result: 0 endpoints
```

**Fix:** Case-sensitive exact match required.

```bash
# Always check:
kubectl get pod --show-labels
# Compare to: kubectl get svc <name> -o jsonpath='{.spec.selector}'
```

---

### ❌ MISTAKE: Selector Syntax Wrong

```bash
# WRONG (kubernetes interprets literally):
selector:
  app: web-server
  version: 1.0

# Pods have labels:
labels:
  app: web  # Doesn't match "web-server"
  version: "1.0"  # Matches (must be string)

# Doesn't match!
```

**Fix:** Exact string match.

---

## RBAC Mistakes

### ❌ MISTAKE: ServiceAccount Doesn't Exist (But You Bound It)

```bash
# Created Role + RoleBinding but no SA:
kubectl create role reader --verb=get --resource=pods
kubectl create rolebinding reader-binding \
  --role=reader \
  --serviceaccount=default:app-sa  # app-sa doesn't exist!

# Binding refs non-existent SA = useless
```

**Fix:** Create SA FIRST.

```bash
kubectl create serviceaccount app-sa
# THEN create role and rolebinding
```

---

### ❌ MISTAKE: Namespace Mismatch in RoleBinding

```bash
# SA in 'default', Role in 'default', but RoleBinding in 'prod':

metadata:
  namespace: prod  # WRONG!

roleRef:
  name: reader

subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: default  # SA is in default

# Binding in different NS = doesn't work
```

**Fix:** All in same namespace.

```bash
# All should have:
metadata:
  namespace: default
```

---

### ❌ MISTAKE: Verb Wrong (Misspelled or Too Restrictive)

```bash
# Role says:
verbs:
  - "get"  # Can only GET

# But app needs to CREATE:
kubectl create deployment...
# FORBIDDEN

# OR typo:
verbs:
  - "gett"  # Typo!
```

**Fix:** Use standard verbs: `get`, `list`, `watch`, `create`, `update`, `delete`, `patch`, `exec`.

---

## Port Mapping Mistakes

### ❌ MISTAKE: Container Port ≠ Service Port

```bash
# Pod runs nginx on port 8080:
containers:
  - image: nginx
    ports:
    - containerPort: 8080

# But service:
ports:
  - port: 80
    targetPort: 80  # WRONG! Should be 8080

# Connection refused
```

**Fix:** Service targetPort must match container port.

```bash
ports:
  - port: 80          # External
    targetPort: 8080  # Container
```

---

### ❌ MISTAKE: Ingress Uses targetPort Instead of Service Port

```bash
# Service:
ports:
  - port: 80           # Service port
    targetPort: 8080   # Container port

# Ingress:
backend:
  service:
    name: myservice
    port:
      number: 8080  # WRONG! Should be 80 (service port)

# 503 Service Unavailable
```

**Fix:** Ingress backend port = service.spec.port (NOT targetPort).

```bash
# Service port is 80, use:
port:
  number: 80
```

---

## Probe Mistakes

### ❌ MISTAKE: Liveness Probe Too Aggressive

```bash
# App takes 30 seconds to start, but:
livenessProbe:
  httpGet:
    path: /health
    port: 80
  initialDelaySeconds: 5  # TOO SHORT!
  failureThreshold: 3

# Kubelet restarts pod 3 times before app even starts
# Pod stuck in CrashLoopBackOff
```

**Fix:** Set initialDelaySeconds >= app startup time.

```bash
livenessProbe:
  httpGet:
    path: /health
    port: 80
  initialDelaySeconds: 30  # Wait for app
  failureThreshold: 3
```

---

### ❌ MISTAKE: Readiness Probe Path Wrong

```bash
# App serves on:
http://localhost:8080/alive

# But probe checks:
readinessProbe:
  httpGet:
    path: /health  # WRONG PATH!
    port: 8080

# Pod never becomes Ready = service excludes it = 0 endpoints
```

**Fix:** Check app documentation for health endpoint.

```bash
readinessProbe:
  httpGet:
    path: /alive  # Correct path
    port: 8080
```

---

## Image Mistakes

### ❌ MISTAKE: Image Tag Doesn't Exist

```bash
# YAML:
image: my-python-app:2.0

# But only 1.0 and 3.0 released
# Result: ImagePullBackOff
```

**Fix:** Check available tags in registry.

```bash
# Use safe defaults:
image: nginx:latest
# OR
image: nginx:1.19
# NOT: image: nginx:99.99
```

---

## ConfigMap/Secret Mistakes

### ❌ MISTAKE: Volume Mount Path Empty

```bash
# ConfigMap created:
kubectl create configmap app-config \
  --from-literal=app.properties="..."

# But volumeMount forgot subPath:
volumeMounts:
  - name: config
    mountPath: /etc/config  # Empty dir!

# App looks for file INSIDE, finds nothing
```

**Fix:** Use correct path or specify file.

```bash
# Option 1: Mount whole configmap
volumeMounts:
  - name: config
    mountPath: /etc/config

# Option 2: Mount specific key
volumeMounts:
  - name: config
    mountPath: /etc/config/app.properties
    subPath: app.properties
```

---

## NetworkPolicy Mistakes

### ❌ MISTAKE: Empty podSelector (Affects ALL pods)

```bash
# NetworkPolicy:
spec:
  podSelector: {}  # THIS MEANS: SELECT ALL PODS!
  policyTypes:
    - Ingress
  ingress: []  # But no allow rules = ALL TRAFFIC BLOCKED

# Everything broken!
```

**Fix:** Specify which pods to protect.

```bash
podSelector:
  matchLabels:
    app: backend  # Protect only these
```

---

### ❌ MISTAKE: Forgot Ingress Rule, Lost Traffic

```bash
# NetworkPolicy created but NO ingress rules:
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  # ingress: [] (empty)

# All traffic blocked (default deny)
```

**Fix:** Add explicit allow rules.

```bash
ingress:
  - from:
      - podSelector:
          matchLabels:
            tier: frontend
```

---

## Context/Cluster Mistakes

### ❌ MISTAKE: Wrong Cluster Context

```bash
$ kubectl config current-context
# aws-cluster-prod

# You edit and think it's dev cluster!
# You delete prod resources instead

# DISASTER
```

**Fix:** Always verify context FIRST.

```bash
# HABIT: Check context before EVERY critical operation
kubectl config current-context

# Or set a PS1 prompt:
export PS1="\[\033[1;34m\]\$(kubectl config current-context)\[\033[0m\]: "
# Now terminal shows current context
```

---

## Commands That Fail Silently

### ❌ MISTAKE: `kubectl describe` instead of `kubectl logs`

```bash
# Pod is crashing, you do:
kubectl describe pod myapp

# You see event: "Back-off restarting failed container"
# But you need the ACTUAL ERROR MESSAGE:
kubectl logs myapp
# Shows: "FileNotFoundError: /app/config.yaml"

# Fix: Always check logs when debugging crashes
```

---

### ❌ MISTAKE: Forgot `--overwrite` When Re-Labeling

```bash
# Pod has: app: old-app
# You try to change:
kubectl label pod myapp app=new-app -n default

# ERROR: label already exists and --overwrite not specified
```

**Fix:** Use `--overwrite`.

```bash
kubectl label pod myapp app=new-app --overwrite
```

---

## Last-Minute Checklist Before Exam Day

- [ ] Practiced RBAC pattern 5× (SA → Role → RoleBinding)
- [ ] Know service selector vs pod labels difference
- [ ] Understand service.port vs service.targetPort vs ingress.port
- [ ] Can list ports for debugging: `kubectl get svc -o wide`
- [ ] Know liveness vs readiness probe behavior
- [ ] Memorized 3 common cron schedules
- [ ] Can fix broken deployment in <3 minutes
- [ ] Know NetworkPolicy default = allow; explicit = deny
- [ ] Can create 5 resources without thinking: SA, Role, RoleBinding, Service, Deployment
- [ ] Have aliases ready: `alias k=kubectl`
- [ ] Know how to check permissions: `kubectl auth can-i`

Practice these 10 things once each.  
You'll recognize the exam questions immediately.

