# 🔧 CKA Diagnostics — Quick Troubleshooting Guide

Use this when things fail during practice or exams. Organized by symptom → diagnosis → fix.

---

## 🔴 Pod Stuck in Pending

**Symptom:** `k get pods` shows `Pending` for 30+ seconds

### Decision Tree

```
1. Are there ANY nodes in the cluster?
   └─ k get nodes
   └─ If none: Cluster infrastructure broken (too big to fix piecemeal)
   
2. Do nodes show as Ready?
   └─ k get nodes -o wide
   └─ If NotReady: see questions/worker-kubelet-config
   └─ If all Ready: Continue to step 3

3. Check Pod events (most useful step)
   └─ k describe pod <pod-name> -n <namespace>
   └─ Look for "Events" section at bottom
   └─ Common messages:
      - "0/3 nodes available: 3 Insufficient memory" → Node RAM too low
      - "0/3 nodes available: 3 node(s) didn't match nodeSelector" → Pod requests specific node
      - "0/3 nodes available: PersistentVolumeClaim is not Bound" → Storage issue (see Storage section)

4. Check resource requests vs node capacity
   └─ k describe pod <pod> | grep -A5 "Requests"
   └─ k top nodes (do nodes have free resources?)
   └─ If pod requests 4GB RAM but node has 2GB: Pod stays Pending

5. Check affinity/tolerations/taints
   └─ k describe node <node-name> | grep -E "Taints|Labels"
   └─ k describe pod <pod> | grep -E "affinity|toleration"
   └─ Pod might be incompatible with node's taints (questions/taint-blocks-scheduling)

6. Still Pending?
   └─ k get events -n <namespace> --sort-by='.lastTimestamp' | tail -5
   └─ Last resort: Check kubelet logs on node → journalctl -u kubelet -f
```

### Quick Fixes

| Message | Fix |
|---------|-----|
| `Insufficient memory` | Delete other pods or increase node RAM |
| `Didn't match nodeSelector` | Remove nodeSelector from Pod or add label to node |
| `PersistentVolumeClaim is not Bound` | See Storage Pending section |
| `Insufficient cpu` | Resource request too high for available nodes |
| `No storage instances available` | Storage class not configured (questions/pending-pvc-storageclass) |

---

## 🔴 PVC (PersistentVolumeClaim) Stuck in Pending

**Symptom:** `k get pvc -n <ns>` shows `Pending` status

### Decision Tree

```
1. Does a matching PV exist?
   └─ k get pv | grep <storage-class>
   └─ If NO: Create PV first (questions/pending-pvc-storageclass)
   └─ If YES: Continue to step 2

2. Is the PV already Bound to another PVC?
   └─ k get pv -o wide | grep <pv-name>
   └─ Look at "CLAIM" column
   └─ If shows "namespace/pvc-name": Already bound, create new PV

3. Does StorageClassName match exactly?
   └─ k get pv <name> -o jsonpath='{.spec.storageClassName}'
   └─ k get pvc <name> -o jsonpath='{.spec.storageClassName}'
   └─ If different: They won't bind. Create new pair with matching class.

4. Does AccessMode match?
   └─ k get pv <name> -o jsonpath='{.spec.accessModes}'
   └─ k get pvc <name> -o jsonpath='{.spec.accessModes}'
   └─ If PV=RWO but PVC=RWX: Won't bind

5. Is capacity sufficient?
   └─ k get pv <name> -o jsonpath='{.spec.capacity.storage}'
   └─ k get pvc <name> -o jsonpath='{.spec.resources.requests.storage}'
   └─ If PV=500Mi but PVC requests 1Gi: Won't bind

6. Still Pending?
   └─ k describe pvc <name> -- check Events section
   └─ Likely messages show exact mismatch (capacity, class, accessMode)
```

### Quick Fixes

| Issue | Fix |
|-------|-----|
| No PV exists | `k create -f pv.yaml` |
| StorageClass mismatch | Delete PVC/PV, recreate with matching class |
| AccessMode mismatch | Change one to match the other |
| Capacity too small | Create larger PV or request less storage |

---

## 🔴 Pod CrashLoopBackOff

**Symptom:** `k get pods` shows `CrashLoopBackOff` for container

### Decision Tree

```
1. Check container logs (most useful step)
   └─ k logs <pod-name> -n <namespace>
   └─ Look for error messages (Java trace, Python exception, etc.)
   
2. Is the image available?
   └─ k describe pod <pod> | grep Image:
   └─ Try: docker pull <image> (does it exist?)
   └─ If not found: Fix image name in YAML

3. Did the container start a process?
   └─ k logs <pod> -- shows stdout/stderr
   └─ If empty: Process exited immediately
   └─ Check Dockerfile: is there a CMD or ENTRYPOINT?

4. Container command failing?
   └─ k get pod <pod> -o yaml | grep -A10 "command:"
   └─ Manual test: can you run this command locally?
   └─ Example: YAML says `command: ["./start.sh"]` but file doesn't exist

5. Still crashing?
   └─ k describe pod <pod> | grep -A20 "Last State"
   └─ Shows exit code: 0 = graceful exit, 1 = error, 137 = killed by system
```

### Quick Fixes

| Exit Code | Cause | Fix |
|-----------|-------|-----|
| 0 | Process completed (not meant to) | Fix ENTRYPOINT or add infinite loop |
| 1 | Command failed | Fix command in YAML, test locally |
| 137 | Out of memory (SIGKILL) | Increase memory limits or reduce usage |
| 126 | Permission denied | Fix file permissions in image |

---

## 🔴 Deployment Stuck at 0/N Replicas

**Symptom:** Scaled deployment but no pods running

### Decision Tree

```
1. Did you create the Deployment?
   └─ k get deployment <name>
   └─ If not found: Create it first

2. Is the Deployment scaled up?
   └─ k get deployment <name> -o jsonpath='{.spec.replicas}'
   └─ If 0: k scale deployment <name> --replicas=3

3. Are replicas trying to run?
   └─ k get pods -l app=<label>
   └─ If no pods: Check step 2 (replica count)
   └─ If Pending pods: See Pod Pending section

4. Check deployment events
   └─ k describe deployment <name> | tail -20
   └─ Look for errors in Events section
```

---

## 🔴 Service Endpoints Empty (No Pods Behind Service)

**Symptom:** `k get endpoints` shows `<none>` for service

### Decision Tree

```
1. Does the service exist?
   └─ k get svc <name>
   └─ If not found: k expose deployment <name> --port=80

2. Does service have a selector?
   └─ k get svc <name> -o yaml | grep selector: -A3
   └─ If no selector: Fix YAML and reapply

3. Do pods match the selector?
   └─ k get pods -l <selector-key>=<selector-value>
   └─ If no pods shown: Labels don't match
   └─ Fix: k label pods <pod> <key>=<value>

4. Are pods Running?
   └─ k get pods -l <selector>
   └─ If Pending/CrashLoop: See Pod sections above
   └─ If Running: Continue to step 5

5. Still no endpoints?
   └─ Service is working correctly
   └─ Problem is somewhere else (pod not listening on port?)
```

---

## 🔴 kubectl Commands Return "Connection Refused"

**Symptom:** `kubectl get pods` or similar says connection refused to localhost:6443

### Decision Tree

```
1. Is the cluster running?
   └─ If using kind: docker ps | grep kca-practice
   └─ If using kubeadm: ssh control-plane; systemctl status kubelet

2. Is kubeconfig set correctly?
   └─ echo $KUBECONFIG
   └─ Or: k config view | head -5
   └─ If empty: source scripts/exam-setup.sh

3. Is API server running?
   └─ k get pods -n kube-system | grep apiserver
   └─ If CrashLoopBackOff: see questions/apiserver-down

4. Can you reach the cluster IP?
   └─ k cluster-info (shows cluster URL)
   └─ curl -k https://127.0.0.1:6443 (should connect or auth error)
   └─ If timeout: Cluster networking is broken

5. Wrong context?
   └─ k config current-context
   └─ k config get-contexts (list all)
   └─ k config use-context <name> (switch context)
```

---

## 🔴 RBAC "forbidden" Error

**Symptom:** `kubectl get pods` returns "forbidden"

### Decision Tree

```
1. Are you using a ServiceAccount?
   └─ echo $KUBECONFIG (check which context/user)
   └─ If running in pod: SA should be mounted at /var/run/secrets/kubernetes.io/serviceaccount

2. Does the SA have RBAC permissions?
   └─ k auth can-i get pods --as=system:serviceaccount:<ns>:<sa>
   └─ If "no": SA lacks permissions

3. Missing Role or RoleBinding?
   └─ k get role -n <ns>
   └─ k get rolebinding -n <ns>
   └─ Verify: rolebinding references role AND SA

4. Check what the SA CAN do
   └─ k auth can-i --list --as=system:serviceaccount:<ns>:<sa>
   └─ Shows all verbs/resources for that SA

### Quick Fix

```bash
# Grant SA read pods permission
k create role pod-reader --verb=get,list --resource=pods -n <ns>
k create rolebinding pod-read --role=pod-reader --serviceaccount=<ns>:<sa> -n <ns>

# Verify
k auth can-i get pods --as=system:serviceaccount:<ns>:<sa>
# Should return "yes"
```

---

## 🔴 Node NotReady

**Symptom:** `k get nodes` shows `NotReady` status

### Decision Tree

```
1. SSH to the node and check systemctl
   └─ systemctl status kubelet
   └─ Should show "active (running)"

2. Check kubelet logs
   └─ journalctl -u kubelet -f (follow logs in real-time)
   └─ Common errors:
      - "x509: certificate has expired" → kubeadm cert issue
      - "no kubelet config" → kubelet config missing
      - "cni plugin not found" → CNI not installed

3. Try restart kubelet
   └─ systemctl restart kubelet
   └─ Wait 30 seconds
   └─ k get nodes (check if Ready now)

4. Check disk/memory on node
   └─ df -h (disk usage)
   └─ free -m (memory usage)
   └─ If 100% disk: Delete large files or pods

5. Still NotReady?
   └─ This is a cluster-multi-fault scenario
   └─ Debug methodically one component at a time
```

---

## 🟡 Metrics Server Not Working

**Symptom:** `k top nodes` returns "metrics not available"

### Decision Tree

```
1. Is metrics-server installed?
   └─ k get deployment -n kube-system | grep metrics
   └─ If not found: Install or use init-cluster.sh which includes it

2. Is metrics-server pod Running?
   └─ k get pods -n kube-system -l k8s-app=metrics-server
   └─ If CrashLoopBackOff: Check logs (k logs -n kube-system <pod>)
   └─ If Pending: See Pod Pending section

3. Wait for metrics to accumulate
   └─ kubectl top works only after ~60 seconds of pod runtime
   └─ If new pod: Wait 90 seconds then retry

4. HPA can't find metrics?
   └─ k get hpa <name> -o yaml | grep "Metrics:"
   └─ If shows "<unknown>/XX%": Pod has no resource.requests (questions/hpa-cpu-autoscaling)
   └─ Fix: Add resources.requests.cpu to Deployment
```

---

## ✅ All Passing? Checklist

Before mock exams:

- [ ] `k get nodes` shows all nodes Ready
- [ ] `k top nodes` returns memory/CPU data
- [ ] `k get pods -A` shows no CrashLoopBackOff pods
- [ ] Services have endpoints: `k get endpoints -A | grep -v "<none>"`
- [ ] Your kubeconfig works: `k auth can-i get pods --as=$(k config get-contexts -o name | head -1)`

If all ✅: Ready for ./cka.

---

**Use this guide when stuck during practice.** 
Each diagnostic takes <2 min. Better than wandering lost.

**Last updated:** June 1, 2026
