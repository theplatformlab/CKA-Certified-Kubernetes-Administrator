# Exercise 05 — NetworkPolicy

> Related: [NetworkPolicy skeleton](../../skeletons/networkpolicy.yaml) | [README — Services & Networking](../../README.md#domain-5--services--networking-20)

Create NetworkPolicies to control pod-to-pod traffic. Watch out for the DNS gotcha.

## Lab Requirements

- Cluster: single-node kind or Minikube
- Components: a CNI that enforces Kubernetes NetworkPolicy; the default CNI may not enforce policies
- Access: permission to create namespaces, Pods, and NetworkPolicies
- Test record: Not tested

## Tasks

1. Create a namespace called `exercise-05`
2. Deploy two pods:
   - `frontend` with image `nginx:1.27` and label `role=frontend`
   - `backend` with image `nginx:1.27` and label `role=backend`
3. Verify that `frontend` can reach `backend` on port 80 (should work before any policy)
4. Create a NetworkPolicy named `backend-policy` that:
   - Applies to pods with label `role=backend`
   - Allows ingress only from pods with label `role=frontend` on port 80
   - Allows egress to DNS (UDP port 53) — if you skip this, DNS breaks
5. Verify that `frontend` can still reach `backend`
6. Create a third pod `attacker` with label `role=attacker` and verify it cannot reach `backend`

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Once you apply any NetworkPolicy to a pod, all traffic not explicitly allowed is denied
- You almost always need to allow DNS egress (UDP port 53), or the pod can't resolve service names
- Test connectivity with `k exec <pod> -- curl -m2 http://<target-ip>`

</details>

## What tripped me up

> I wrote a perfect ingress rule but forgot egress entirely. The backend pod could receive traffic but couldn't respond to DNS lookups — so any test using service names failed. I thought my ingress rule was wrong and spent 8 minutes rewriting it. The fix was two lines: allow UDP 53 egress. I've made this mistake three separate times during practice. Now I write the DNS egress rule FIRST, before anything else.
>
> AND vs OR tripped me up too. Two selectors in the *same* `from` block = AND (must match both). Two separate `from` blocks = OR (match either). I had `podSelector` and `namespaceSelector` in separate blocks when they should have been in the same one — it allowed traffic from any pod in the right namespace OR any pod with the right label in any namespace.

## Verify

```bash
# Get backend IP
BACKEND_IP=$(k get pod backend -n exercise-05 -o jsonpath='{.status.podIP}')

# Frontend -> Backend: should work
k exec frontend -n exercise-05 -- curl -m2 http://$BACKEND_IP

# Attacker -> Backend: should time out
k exec attacker -n exercise-05 -- curl -m2 http://$BACKEND_IP
```

## CNI Troubleshooting

NetworkPolicy assumes the Container Network Interface (CNI) is installed and working. If pods can't communicate at all, NetworkPolicy isn't the problem — CNI is.

### Verify CNI is running

```bash
# Check if CNI pods are deployed (usually in kube-system or calico-system)
k get pods -n kube-system | grep -i cni
k get pods -n kube-system | grep -i calico
k get pods -n calico-system

# Check if CNI daemonset is running on all nodes
k get daemonset -n kube-system
k get daemonset -n calico-system

# Verify CNI configuration files exist on nodes
ssh <node> ls -la /etc/cni/net.d/
ssh <node> ls -la /opt/cni/bin/

# Check kubelet is configured to use CNI
ssh <node> cat /etc/kubernetes/kubelet.conf | grep cni
```

### Common CNI issues

**Pods can't communicate even without NetworkPolicy:**
- CNI plugin not deployed (check kube-system pods)
- Kubelet CNI configuration missing (check /etc/kubernetes/kubelet.conf)
- CNI binary not present on node (check /opt/cni/bin/)
- Pod IP is 10.244.x.x but nodes can't route to it

**Pod networking works but DNS fails:**
- CoreDNS pod can't reach internet (check CoreDNS pod events)
- CNI doesn't allow DNS traffic by default
- firewalld or iptables blocking DNS on the node

**NetworkPolicy appears to block everything:**
- CNI not configured for network policies (Calico needs NetworkPolicy RBAC and CRD)
- NetworkPolicy controller not running (check events on policies)
- Existing policies deny all traffic by default

### Debug pod network when connectivity fails

```bash
# Check if pod has an IP address
k get pod frontend -n exercise-05 -o wide

# If pod is CrashLoopBackOff or can't get IP:
k describe pod frontend -n exercise-05  # Check Events section
k logs frontend -n exercise-05  # Check for startup errors

# If pod has IP but can't connect to another pod:
# Step 1: Ping from pod to pod
k exec frontend -n exercise-05 -- ping -c 2 <backend-pod-ip>

# Step 2: Check if routes exist on node
ssh <node> ip route show | grep 10.244

# Step 3: Check CNI plugin logs
ssh <node> journalctl -u kubelet -n 50  # Kubelet logs
ssh <node> journalctl -u cri-docker -n 50  # Container runtime logs
ssh <node> tail -f /var/log/calico/calico.log  # If using Calico

# Step 4: Check iptables rules created by CNI
ssh <node> sudo iptables -L -n
ssh <node> sudo iptables -L -n -t nat

# Step 5: Verify service connectivity
k exec frontend -n exercise-05 -- curl -m2 http://kubernetes.default.svc.cluster.local
k exec frontend -n exercise-05 -- nslookup kubernetes.default
```

### Before blaming NetworkPolicy

1. Verify pods get IPs: `k get pod -n exercise-05 -o wide`
2. Test without NetworkPolicy: `k delete netpol --all -n exercise-05` then test connectivity
3. If connectivity works without the policy but fails with it, then the NetworkPolicy is the problem
4. If connectivity fails even without the policy, debug CNI first

## Cleanup

```bash
k delete ns exercise-05
```

<details>
<summary>Solution</summary>

```bash
k create ns exercise-05

# Create pods
k run frontend -n exercise-05 --image=nginx:1.27 --labels=role=frontend
k run backend -n exercise-05 --image=nginx:1.27 --labels=role=backend
k run attacker -n exercise-05 --image=nginx:1.27 --labels=role=attacker

# Wait for all pods
k get pods -n exercise-05 -w
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: exercise-05
spec:
  podSelector:
    matchLabels:
      role: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
```

```bash
k apply -f netpol.yaml

# Test
BACKEND_IP=$(k get pod backend -n exercise-05 -o jsonpath='{.status.podIP}')
k exec frontend -n exercise-05 -- curl -m2 http://$BACKEND_IP
k exec attacker -n exercise-05 -- curl -m2 http://$BACKEND_IP
```

</details>
