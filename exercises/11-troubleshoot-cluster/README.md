# Exercise 11 — Troubleshoot Cluster Components

> Related: [README — Troubleshooting](../../README.md#domain-2--troubleshooting-30) | **Updated May 2026**

Fix a broken cluster. This exercise simulates common failures you'll see on the CKA: kubelet down, kube-proxy misconfigured, CoreDNS not resolving.

## Conventions

Before working through these scenarios, understand the trap architecture:

- **Primary Trap:** A legitimate cluster misconfiguration that breaks functionality (e.g., kubelet service stopped)
- **Secondary Trap (Gotcha):** A realistic red herring that makes diagnosis harder (e.g., checking wrong `kubeconfig` context, nodes showing status from wrong cluster)
- **Validation Criteria:** Your answer is correct if:
  - The cluster component is running and healthy
  - All nodes return to `Ready` or services return to running state
  - Subsequent `kubectl` commands work without errors
  - You've identified the root cause, not just the symptom

**Scoring:** Full credit for fixing the issue + explaining the root cause. Partial credit for fixing without explanation.

## Tasks

This exercise runs on the ops cluster (`./scripts/init-cluster.sh --profile ops`; `./scripts/lab.sh setup 11` breaks it — don't look at what it changes). The cluster is broken in four places at once, one fault per scenario below; the tasks only describe symptoms. Work in namespace `exercise-11`.

Nodes are `cka-ops-control-plane` and `cka-ops-worker`. Open a shell on a node with `docker exec -it <node> bash` — the kind equivalent of `ssh <node>` in the exam.

The check reports each scenario separately (`[A]` ... `[D]`), so you can fix them in any order. Faults can mask each other: a symptom may change after you fix another scenario — re-test after every fix.

### Scenario A: Broken kubelet

1. `k get nodes` shows `cka-ops-worker` as `NotReady`
2. Open a shell on the worker and check the kubelet service status and logs
3. Fix it so the node returns to `Ready` — and stays fixed after the node reboots

### Scenario B: CoreDNS troubleshooting

1. From a test pod, resolving `kubernetes.default.svc.cluster.local` fails
2. Check CoreDNS pods in `kube-system`
3. Check CoreDNS logs for errors
4. Verify the CoreDNS ConfigMap for misconfigurations
5. Check that the `kube-dns` service has endpoints
6. Fix any issues and verify DNS resolution works from a pod

### Scenario C: kube-proxy

The Service `web` in `exercise-11` has a Ready backend pod, but nothing answers on its ClusterIP.

1. Check if kube-proxy pods are running on all nodes
2. Check kube-proxy logs
3. Verify kube-proxy ConfigMap
4. Check iptables rules for the Service on a node
5. Fix it: `wget -qO- http://<ClusterIP of web>` from a test pod returns the nginx page

### Scenario D: API Server audit logs (Kubernetes 1.35 troubleshooting)

The API server writes an audit log. A ServiceAccount tried to delete the Secret `db-credentials` in `exercise-11` and was denied by RBAC.

1. Find where audit logs are stored on the control plane node
2. Check the audit policy configuration in the apiserver manifest
3. Find requests that were denied by RBAC (there is more than one)
4. Find the identity whose *delete* of Secret `db-credentials` was denied
5. Write its full username exactly as the audit log shows it (`system:serviceaccount:<namespace>:<name>`) to `/opt/exercise-11/denied-user.txt` on `cka-ops-control-plane`

Validate with `./scripts/lab.sh check 11`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `systemctl status kubelet` and `journalctl -u kubelet` for kubelet issues
- CoreDNS pods run as a Deployment in `kube-system`
- `k exec <pod> -- nslookup kubernetes` to test DNS
- kube-proxy runs as a DaemonSet in `kube-system`
- `iptables-save | grep <service-name>` to check kube-proxy rules (kube-proxy comments its rules with `<namespace>/<service>`)
- A ConfigMap change only reaches kube-proxy when its pods restart
- Audit logs typically at `/var/log/audit/audit.log` or `/var/log/kubernetes/audit/audit.log`
- Check `/etc/kubernetes/manifests/kube-apiserver.yaml` for `--audit-log-path` and `--audit-policy-file`
- `jq` is installed on the control plane node
- Look for `"verb":"delete"` or `"user":{"username":"system:admin"}` in audit logs to find specific operations

</details>

## What tripped me up

> **Kubelet Trap:** My first instinct when a node is NotReady was to run `kubectl describe node` from the control plane. That gives you conditions but not the root cause. The real answer is almost always in `journalctl -u kubelet` on the broken node itself. SSH first, check kubelet logs, then work backwards. I wasted 7 minutes on practice exam questions by troubleshooting from the wrong machine.
>
> **Kubelet Gotcha (Red Herring):** In k8s v1.35, the systemd service is `kubelet`, but the process might have a different PID if running in a container. Don't assume `ps aux | grep kubelet` shows the main process. Always use `systemctl status kubelet` for authoritative state.
>
> **CoreDNS Trap:** `nslookup` failing doesn't always mean CoreDNS is broken. Check `resolv.conf` inside the pod first — I had a case where the pod's DNS config was pointing to the wrong IP because of a network policy blocking UDP 53 to the kube-dns service. The CoreDNS pods were fine; the traffic just couldn't reach them. Verify: `k exec <pod> -- cat /etc/resolv.conf`
>
> **CoreDNS Gotcha (May 2026):** In k8s 1.35+, CoreDNS respects search domain order. If your test pod gets DNS timeout, check the search domains in `resolv.conf` — they're often set by the kubelet's `--cluster-domain` flag. A misconfigured search domain can cause subtle timeouts (too many attempted SRV records).
>
> **kube-proxy Trap:** Not all nodes have kube-proxy running. In some environments (e.g., kind, GKE with eBPF mode), kube-proxy may not exist. Check the actual cluster setup before assuming kube-proxy absence = failure. Always verify: `k get ds -n kube-system | grep proxy` or `k get pods -n kube-system -l k8s-app=kube-proxy`.
>
> **Audit Logs Gotcha:** I initially searched `grep "error"` which gave me nothing useful. The audit log format is JSON — you need to grep for specific verb patterns like `grep "verb.*delete"` or look for status codes. Also, not all clusters enable audit logging, so check if the apiserver was even started with audit flags before spending time looking for logs that don't exist. **May 2026 update:** Use `jq` if available: `cat /var/log/audit/audit.log | jq 'select(.user.username=="admin")' | jq '.verb'`

## Verify

```bash
./scripts/lab.sh check 11
```

Manual checks:

```bash
# All nodes Ready
k get nodes

# DNS works
k -n exercise-11 run test-dns --image=busybox:1.37 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local

# Services are routable
k -n exercise-11 get svc web
k -n exercise-11 run test-web --image=busybox:1.37 --rm -it --restart=Never -- \
  wget -qO- http://<ClusterIP of web>

# Your audit answer
docker exec cka-ops-control-plane cat /opt/exercise-11/denied-user.txt
```

## Cleanup

```bash
./scripts/lab.sh cleanup 11
```

Cleanup repairs whatever is still broken (kubelet, CoreDNS, kube-proxy), removes the audit logging from the API server and deletes the namespace.

<details>
<summary>Solution</summary>

### Scenario A: kubelet

```bash
k get nodes
# cka-ops-worker   NotReady

# Shell on the worker (exam: ssh cka-ops-worker)
docker exec -it cka-ops-worker bash

# Check why
systemctl status kubelet
# Loaded: ... kubelet.service; disabled ...   Active: inactive (dead)
journalctl -u kubelet --no-pager | tail -30
# Nothing crashed: the service was stopped and disabled

# Fix: start it AND enable it, so it comes back after a reboot
systemctl enable --now kubelet
exit

k get nodes
# cka-ops-worker should be Ready again after a few seconds
```

### Scenario B: CoreDNS

```bash
# Test DNS
k -n exercise-11 run test-dns --image=busybox:1.37 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
# NXDOMAIN (or a timeout while kube-proxy is still broken — Scenario C)

# Check CoreDNS pods and logs
k get pods -n kube-system -l k8s-app=kube-dns
k logs -n kube-system -l k8s-app=kube-dns

# Check endpoints
k get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
# Should show IPs of CoreDNS pods — they are fine

# Check ConfigMap
k get configmap coredns -n kube-system -o yaml
# kubernetes cluster.lcoal in-addr.arpa ip6.arpa {   <- typo: the zone must be cluster.local

# Fix the typo and restart CoreDNS (the reload plugin would pick it up too, but slower)
k edit configmap coredns -n kube-system
k -n kube-system rollout restart deployment coredns
k -n kube-system rollout status deployment coredns

# Test DNS again
k -n exercise-11 run test-dns --image=busybox:1.37 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
```

### Scenario C: kube-proxy

```bash
# Check DaemonSet and pods
k get ds kube-proxy -n kube-system
k get pods -n kube-system -l k8s-app=kube-proxy -o wide
# 0/1 CrashLoopBackOff on every node

# Check logs
k logs -n kube-system -l k8s-app=kube-proxy | tail -20
# "command failed" err="failed validate: KubeProxyConfiguration.Mode.ProxyMode: Invalid value: \"iptable\" ..."

# On a node, there are no rules for the Service web (created after kube-proxy died)
docker exec cka-ops-worker iptables-save | grep exercise-11/web

# Fix the ConfigMap: mode: iptables
k edit configmap kube-proxy -n kube-system

# Restart the pods so they read the new config
k -n kube-system delete pod -l k8s-app=kube-proxy
k -n kube-system rollout status ds kube-proxy

# Rules exist now and the ClusterIP answers
docker exec cka-ops-worker iptables-save | grep -c exercise-11/web
k -n exercise-11 run test-web --image=busybox:1.37 --rm -it --restart=Never -- \
  wget -qO- http://$(k -n exercise-11 get svc web -o jsonpath='{.spec.clusterIP}')
```

### Scenario D: API Server audit logs

```bash
# Shell on the control plane (exam: ssh cka-ops-control-plane)
docker exec -it cka-ops-control-plane bash

# Check apiserver manifest for audit configuration
grep -i audit /etc/kubernetes/manifests/kube-apiserver.yaml
# --audit-policy-file=/etc/kubernetes/audit/policy.yaml
# --audit-log-path=/var/log/kubernetes/audit/audit.log
cat /etc/kubernetes/audit/policy.yaml

# Check request count by verb
jq -r '.verb' /var/log/kubernetes/audit/audit.log | sort | uniq -c | sort -rn

# All requests denied by RBAC (403) — there is a denied get as a red herring
jq -c 'select(.responseStatus.code==403) | [.user.username, .verb, .objectRef.resource, .objectRef.name]' \
  /var/log/kubernetes/audit/audit.log

# The denied delete of Secret db-credentials
jq -r 'select(.verb=="delete" and .objectRef.resource=="secrets"
              and .objectRef.name=="db-credentials" and .responseStatus.code==403)
       | .user.username' /var/log/kubernetes/audit/audit.log | sort -u

# Write the answer
mkdir -p /opt/exercise-11
echo "system:serviceaccount:exercise-11:<name from the query above>" > /opt/exercise-11/denied-user.txt
exit

./scripts/lab.sh check 11
```

</details>
