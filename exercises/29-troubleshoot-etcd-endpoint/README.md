# Exercise 29 — Troubleshoot Broken Cluster (Incorrect etcd Endpoint)

> Related: [README — Cluster Maintenance](../../README.md#domain-7--cluster-maintenance-11) | **Updated May 2026**

Debug and fix a broken control plane where API server points to wrong etcd endpoint. Tests troubleshooting methodology and static pod modification.

## Lab Requirements

- Cluster: disposable kubeadm control-plane node with local etcd
- Components: kube-apiserver static pod, kubelet, etcd manifest and certificates
- Access: SSH or direct shell access to the control-plane node; sudo required
- Test record: Not tested

## Conventions

Trap architecture for this exercise:

- **Primary Trap:** API server misconfigured to point to wrong etcd endpoint (wrong IP, wrong port, or wrong protocol)
- **Secondary Trap (Gotcha):** Static pod not restarting due to kubelet watching race condition, or multiple etcd instances running (one broken one working)
- **Validation Criteria:** Your answer is correct if:
  - API server pod transitions from `CrashLoopBackOff` to `Running` within 30 seconds
  - `k get nodes` and `k get pods -A` execute successfully
  - etcd connection string matches `/etc/kubernetes/manifests/etcd.yaml` exactly
- **Scoring:** Full credit for fix + explanation of root cause. Partial for fix alone.

## Tasks

1. Cluster is broken: API server won't start
2. Check kube-apiserver pod logs
3. Find the error: incorrect etcd endpoint IP or port
4. SSH into control plane node
5. Edit `/etc/kubernetes/manifests/kube-apiserver.yaml`
6. Correct the etcd endpoint in `--etcd-servers=` flag
7. Verify IP/port matches `/etc/kubernetes/manifests/etcd.yaml`
8. Save and wait for API server to restart
9. Verify cluster is healthy:
   - `k get nodes` works
   - `k get pods -A` works
   - API server is Running

## Key Learning

- Static pods in `/etc/kubernetes/manifests/` auto-restart on file changes
- API server cannot start without etcd connection
- etcd endpoint must be exact: `https://127.0.0.1:2379` or `https://<etcd-ip>:2379`
- Troubleshooting: check pod logs first, then manifest
- Exam tests understanding of control plane components

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Check kube-apiserver logs: `k logs -n kube-system kube-apiserver-<node>` (if APIserver partially runs)
- If logs unavailable, SSH to node and check: `journalctl -u kubelet -f`
- Get correct etcd endpoint: `grep "\-\-listen-client-urls" /etc/kubernetes/manifests/etcd.yaml`
- Edit manifest: `sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml`
- Look for line: `--etcd-servers=https://...`
- After fix, wait 10-15 seconds for pod to restart

</details>

## What tripped me up

> **Static Pod Trap:** I found the wrong IP in kube-apiserver but didn't think to verify the CORRECT IP by checking etcd.yaml. Edited to what I thought was right and it was still wrong. **Always verify from source.** The correct etcd endpoint is the source of truth — never guess.
>
> **Static Pod Gotcha:** I tried to `kubectl apply` the manifest — that doesn't work for static pods. Must edit in place in `/etc/kubernetes/manifests/`. The kubelet watches that directory and auto-restarts pods when files change. **May 2026 update:** kubelet file watching can have race conditions on very fast SSDs. If the pod doesn't restart within 10 seconds, try: `sudo systemctl restart kubelet` (on the control plane node only).
>
> **Certificate Gotcha (v1.35):** In k8s 1.35, etcd certificate validation is stricter. If switching etcd endpoints, verify both use the same certificate scheme (self-signed vs CA-signed). A mismatch causes `x509: certificate signed by unknown authority` errors. Check: `grep "client-cert-auth" /etc/kubernetes/manifests/etcd.yaml` must match the connection string security flags.
>
> **Port Gotcha:** etcd default is `2379` (client port), not `2384` (peer port). Common mistake: `--etcd-servers=https://127.0.0.1:2384` (peer port) instead of `2379`. Always verify in the etcd manifest: `grep "listen-client-urls" /etc/kubernetes/manifests/etcd.yaml`.
>
> **Hostname vs IP Trap:** Some clusters use etcd hostnames (e.g., `etcd-0`) instead of IPs. If the manifest says `--etcd-servers=https://etcd-0:2379` but the error says "name resolution failed", this is actually correct — DNS isn't working because the API server pod is broken. Don't try to change hostname to IP (that breaks HA clusters). Instead, fix the connection string format.

## Verify

```bash
# Check no errors in logs
k logs -n kube-system kube-apiserver-<node-name> | tail -20

# API server is Running
k get pod -n kube-system kube-apiserver-<node-name>

# Basic cluster operations work
k get nodes
k get pods -A
k api-resources
```

## Cleanup

Cluster is now fixed. Nothing to clean up.

<details>
<summary>Solution</summary>

```bash
# 1. Check if API server is running (it may be stuck/restarting)
k get pod -n kube-system -l component=kube-apiserver

# 2. If accessible, check logs
k logs -n kube-system kube-apiserver-<node> --tail=50
# Look for error like: "dial tcp 10.0.0.5:2379: connection refused"

# 3. SSH into control plane node
ssh <control-plane-ip>

# 4. Check current etcd endpoint in API server manifest
grep "etcd-servers" /etc/kubernetes/manifests/kube-apiserver.yaml
# Example: --etcd-servers=https://10.0.0.5:2379

# 5. Get CORRECT endpoint from etcd manifest
grep "listen-client-urls" /etc/kubernetes/manifests/etcd.yaml
# Example: --listen-client-urls=https://127.0.0.1:2379,https://10.0.0.10:2379

# 6. The correct endpoint should be one from etcd's listen URLs
# Usually: https://127.0.0.1:2379 (if etcd on same node)
# Or: https://<etcd-ip>:2379 (if separate etcd node)

# 7. Edit and fix
sudo sed -i 's|--etcd-servers=https://10.0.0.5:2379|--etcd-servers=https://127.0.0.1:2379|' /etc/kubernetes/manifests/kube-apiserver.yaml

# Or manually edit
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Find and correct the etcd-servers line

# 8. Save (vi: Esc, :wq)
# kubelet will auto-detect change and restart pod

# 9. Verify API server comes up (may take 10-15 seconds)
k get pod -n kube-system kube-apiserver-<node-name>
# STATUS should change from CrashLoopBackOff to Running

# 10. Test cluster is working
k get nodes
k version
```

</details>
