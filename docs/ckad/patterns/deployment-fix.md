# Deployment Debugging Pattern

**Curriculum domain:** Application Observability and Maintenance (15%, debugging) and Application Deployment (20%)

---

## Problem Scenario

> Fix the deployment 'api-server' in namespace 'default'. Pods are stuck in CrashLoopBackOff.

---

## Diagnosis Methodology (Use This Every Time)

### Step 1: Check Pod Status
```bash
kubectl get pod -l app=api-server
# NAME                         READY   STATUS             RESTARTS
# api-server-778c6d4b98-xyz    0/1     CrashLoopBackOff   3 (2m ago)
```

### Step 2: Get Detailed Status
```bash
kubectl describe pod <pod-name>
# Look for:
# - Image pull errors (ImagePullBackOff)
# - Liveness/Readiness probe failures (Killing container)
# - Missing volume/secret
```

### Step 3: Check Logs
```bash
kubectl logs <pod-name>
# Error: cannot find application.config
# OR wrong port
# OR permission denied
```

### Step 4: Identify Root Cause

| Symptom | Fix |
|---------|-----|
| `ImagePullBackOff` | Image name wrong or doesn't exist; image pull secret missing |
| `Segmentation fault` / `SIGKILL` | Memory limit too low; app crash (check logs) |
| `Connection refused` | Wrong port; app not listening; liveness probe too aggressive |
| `File not found` | Volume not mounted; ConfigMap/Secret missing key |
| `Permission denied` | Security context issue; container running as wrong user |

---

## Common Exam Fixes

### Fix 1: Wrong Image
```bash
# Check current image
kubectl get deployment api-server -o jsonpath='{.spec.template.spec.containers[0].image}'

# Fix it
kubectl set image deployment/api-server \
  api-server=nginx:1.19 \
  --record
```

### Fix 2: Wrong Port/Command
```bash
# Edit and fix command/args
kubectl edit deployment api-server

# OR replace via YAML
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api-server
        image: myregistry.io/api:latest
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
EOF
```

### Fix 3: Missing ConfigMap/Secret
```bash
# Create ConfigMap if missing
kubectl create configmap app-config \
  --from-literal=key=value \
  -n default

# Then mount it in deployment
kubectl set env deployment/api-server \
  CONFIGMAP_MOUNTED=true
```

### Fix 4: Resource Limits Too Low
```bash
kubectl set resources deployment api-server \
  --limits=cpu=500m,memory=512Mi \
  --requests=cpu=250m,memory=256Mi
```

---

## Verification Pattern

```bash
# 1. Check deployment
kubectl get deployment api-server
# Should show: READY 3/3, UP-TO-DATE 3/3, AVAILABLE 3/3

# 2. Check pods
kubectl get pod -l app=api-server
# All should be: READY 1/1, STATUS Running

# 3. Check logs (no errors)
kubectl logs -l app=api-server --all-containers=true

# 4. Test connectivity
kubectl port-forward svc/api-server 8080:80
# Then curl http://localhost:8080
```

---

## Time Pressure Tips

- **Don't edit deployment manually** → Use `kubectl set` commands (faster, less error-prone)
- **Don't recreate** → Fix existing deployment
- **Check logs first** → Saves 10 minutes of guessing
- **Common culprit** → Readiness/Liveness probe timing (increase `initialDelaySeconds` to 20-30)

---

## Exam Scenario Variations

- Pod pending (not CrashLoop) → Check PVC, node affinity, resource requests
- Image pull failing → Add ImagePullSecret (usually provided in exam)
- App needs ConfigMap but it doesn't exist → Create it exam will tell you the key/value
- Wrong number of replicas → Fix `.spec.replicas`
