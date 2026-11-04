# Ingress Debugging Pattern

**Curriculum domain:** Services and Networking (20%)

---

## Problem Scenario

> Ingress is created but external traffic not reaching the backend service. Debug and fix.

---

## Diagnosis Checklist

```bash
# 1. Ingress exists?
kubectl get ingress
kubectl describe ingress <name>

# 2. Service exists and has endpoints?
kubectl get svc <backend-service>
kubectl get endpoints <backend-service>
# CRITICAL: Endpoints must be non-empty, else service selector wrong

# 3. Pods running?
kubectl get pod -l <label-from-service-selector>

# 4. Port mapping correct?
kubectl get svc -o wide
# Check: containerPort matches service targetPort

# 5. Ingress rules correct?
kubectl get ingress -o yaml | grep -A 10 "rules:"
```

---

## Common Ingress + Service Fix Pattern

### YAML Template

```yaml
---
# 1. Service (backend)
apiVersion: v1
kind: Service
metadata:
  name: myapp-svc
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: myapp  # MUST match pod labels exactly
  ports:
    - port: 80          # Service port
      targetPort: 8080  # Container port
      protocol: TCP

---
# 2. Ingress (frontend)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx  # Check with: kubectl get ingressclass
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-svc      # Must match service name
                port:
                  number: 80         # Must match service port (not targetPort)
```

---

## Quick Creation Commands

```bash
# 1. Create deployment
kubectl create deployment myapp --image=nginx --replicas=2

# 2. Create service
kubectl expose deployment myapp --port=80 --target-port=80 --name=myapp-svc

# 3. Create ingress (command line)
kubectl create ingress myapp-ingress \
  --class=nginx \
  --rule="myapp.example.com/*=myapp-svc:80"

# 4. Verify
kubectl get ingress
kubectl get endpoints myapp-svc
```

---

## Fix Common Issues

### Issue 1: Service Selector Mismatch
```bash
# Check pod labels
kubectl get pod --show-labels

# Check service selector
kubectl get svc myapp-svc -o jsonpath='{.spec.selector}'
# {"app":"myapp"}

# If wrong, recreate or edit
kubectl edit svc myapp-svc
# Change selector.app to match pod label
```

### Issue 2: Port Mismatch
```bash
# Get all ports in chain
kubectl get svc myapp-svc -o yaml
# spec.ports.port = 80 (service)
# spec.ports.targetPort = 8080 (container)

# Ingress MUST use spec.port (80, not 8080)
kubectl get ingress myapp-ingress -o yaml | grep "port:"
# Should be:
#   number: 80  (not 8080)
```

### Issue 3: No Endpoints
```bash
kubectl get endpoints myapp-svc
# Output should show IP:port, not empty

# If empty, service selector doesn't match any pods
kubectl get pod --show-labels
# Pod labels must match: selector in service
```

### Issue 4: Ingress Class Wrong
```bash
# Check available ingress classes
kubectl get ingressclass

# Fix in ingress
kubectl get ingress myapp-ingress -o yaml | grep "ingressClassName:"
# Common values: nginx, traefik, aws-alb
```

---

## Verification Pattern

```bash
# 1. Can you reach service from within cluster?
kubectl run test-pod --image=curl -it -- curl http://myapp-svc

# 2. Check ingress status
kubectl describe ingress myapp-ingress
# Look for: Address, Hosts, Rules

# 3. Test external access (if ingress controller is setup)
curl -H "Host: myapp.example.com" http://<ingress-ip>/

# 4. Check logs
kubectl logs -l app=myapp
kubectl logs -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx
```

---

## Exam Variations

| Scenario | Fix |
|----------|-----|
| Path-based routing | Add multiple paths to same ingress; different backends per path |
| TLS required | Add `tls:` section with secret reference |
| Service in different namespace | Use `myapp-svc.other-namespace.svc.cluster.local` |
| Port not 80 | Specify correct `port.number` in ingress |
| RewriteTarget needed | Add annotation: `nginx.ingress.kubernetes.io/rewrite-target: /` |

---

## Speed Checklist

- [ ] Service exists? `kubectl get svc`
- [ ] Service has endpoints? `kubectl get endpoints` (not empty)
- [ ] Pod labels match service selector? `kubectl get pod --show-labels`
- [ ] Ingress service backend name correct?
- [ ] Ingress service port = svc.spec.port (NOT targetPort)?
- [ ] Ingress class exists? `kubectl get ingressclass`
