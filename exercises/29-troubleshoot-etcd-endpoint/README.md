# Exercise 29 — Troubleshoot a Broken Control Plane

> Related: [README — Cluster Maintenance](../../README.md#domain-7--cluster-maintenance-11) | **Updated May 2026**

The cluster's API server doesn't come up any more. Find the cause and fix it. Practises troubleshooting with the container runtime and static pod manifests.

## Conventions

Trap architecture for this exercise:

- **Primary Trap:** API server misconfigured to point to wrong etcd endpoint (wrong IP, wrong port, or wrong protocol)
- **Secondary Trap (Gotcha):** Static pod not restarting due to kubelet watching race condition, or multiple etcd instances running (one broken one working)
- **Validation Criteria:** Your answer is correct if:
  - API server pod transitions from `CrashLoopBackOff` to `Running` within 30 seconds
  - `k get nodes` and `k get pods -A` execute successfully
  - `--etcd-servers` matches one of etcd's `--listen-client-urls` in `/etc/kubernetes/manifests/etcd.yaml` exactly
- **Scoring:** Full credit for fix + explanation of root cause. Partial for fix alone.

## Tasks

This exercise runs on the ops cluster (`./scripts/init-cluster.sh --profile ops`; `./scripts/lab.sh setup 29` breaks it — don't look at what it changes). The control plane node is `cka-ops-control-plane`: `ssh cka-ops-control-plane` in the lab shell (or `docker exec -it cka-ops-control-plane bash`).

1. `k get nodes` no longer answers. Find out why and fix it — verify the correct values against the configuration of the components involved, don't guess.
2. Afterwards the cluster must be healthy:
   - `k get nodes` works and all nodes are `Ready`
   - `k get pods -A` works
   - the `kube-apiserver-cka-ops-control-plane` pod is Running and Ready

Validate with `./scripts/lab.sh check 29`.

## Key Learning

- Static pods in `/etc/kubernetes/manifests/` auto-restart on file changes
- API server cannot start without etcd connection
- etcd endpoint must be exact: `https://127.0.0.1:2379` or `https://<etcd-ip>:2379`
- Troubleshooting: check pod logs first, then manifest
- Exam tests understanding of control plane components

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Open a shell on the control plane node. With the API down, `k logs` fails. On the node: `crictl ps -a | grep kube-apiserver`, then `crictl logs <container-id>`
- The same logs are on disk: `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/`
- `journalctl -u kubelet -f` shows the kubelet (re)starting the static pod
- Get correct etcd endpoint: `grep "\-\-listen-client-urls" /etc/kubernetes/manifests/etcd.yaml`
- Edit manifest: `vi /etc/kubernetes/manifests/kube-apiserver.yaml`
- Look for line: `--etcd-servers=https://...`
- After the fix, wait 30-60 seconds for the pod to restart and become Ready

</details>

## What tripped me up

> **Static Pod Trap:** I found the wrong IP in kube-apiserver but didn't think to verify the CORRECT IP by checking etcd.yaml. Edited to what I thought was right and it was still wrong. **Always verify from source.** The correct etcd endpoint is the source of truth — never guess.
>
> **Static Pod Gotcha:** I tried to `kubectl apply` the manifest — that doesn't work for static pods. Must edit in place in `/etc/kubernetes/manifests/`. The kubelet watches that directory and auto-restarts pods when files change. **May 2026 update:** kubelet file watching can have race conditions on very fast SSDs. If the pod doesn't restart within 10 seconds, try: `sudo systemctl restart kubelet` (on the control plane node only).
>
> **Certificate Gotcha (v1.35):** In k8s 1.35, etcd certificate validation is stricter. If switching etcd endpoints, verify both use the same certificate scheme (self-signed vs CA-signed). A mismatch causes `x509: certificate signed by unknown authority` errors. Check: `grep "client-cert-auth" /etc/kubernetes/manifests/etcd.yaml` must match the connection string security flags.
>
> **Port Gotcha:** etcd default is `2379` (client port), not `2380` (peer port). Common mistake: `--etcd-servers=https://127.0.0.1:2380` (peer port) instead of `2379`. Always verify in the etcd manifest: `grep "listen-client-urls" /etc/kubernetes/manifests/etcd.yaml`.
>
> **Hostname vs IP Trap:** Some clusters use etcd hostnames (e.g., `etcd-0`) instead of IPs. If the manifest says `--etcd-servers=https://etcd-0:2379` but the error says "name resolution failed", this is actually correct — DNS isn't working because the API server pod is broken. Don't try to change hostname to IP (that breaks HA clusters). Instead, fix the connection string format.

## Verify

```bash
./scripts/lab.sh check 29
```

Manual checks:

```bash
# API server is Running and Ready
k get pod -n kube-system kube-apiserver-cka-ops-control-plane

# Check no errors in logs
k logs -n kube-system kube-apiserver-cka-ops-control-plane | tail -20

# Basic cluster operations work
k get nodes
k get pods -A
k api-resources
```

## Cleanup

Nothing to clean up once the cluster is fixed. If you give up, `./scripts/lab.sh cleanup 29` restores the API server's etcd endpoint.

<details>
<summary>Solution</summary>

```bash
# 1. The API server is not answering
k get nodes
# Unable to connect to the server / connection refused / timeout

# 2. Shell on the control plane node (exam: ssh cka-ops-control-plane)
docker exec -it cka-ops-control-plane bash

# 3. Find the API server container (it keeps exiting and restarting) and read its logs
crictl ps -a | grep kube-apiserver
crictl logs <container-id> 2>&1 | tail -20
# grpc: addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2397", ...}
#   Err: connection error: ... connect: connection refused

# 4. Current etcd endpoint in the API server manifest
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
# - --etcd-servers=https://127.0.0.1:2397

# 5. CORRECT endpoint from the etcd manifest (source of truth)
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml
# - --listen-client-urls=https://127.0.0.1:2379,https://<node-ip>:2379
# 2397 is a typo for 2379

# 6. Fix in place (or: vi /etc/kubernetes/manifests/kube-apiserver.yaml)
sed -i 's|--etcd-servers=https://127.0.0.1:2397|--etcd-servers=https://127.0.0.1:2379|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml

# kubelet detects the change and recreates the pod
watch crictl ps --name kube-apiserver
exit

# 7. Verify (may take 30-60 seconds)
k get pod -n kube-system kube-apiserver-cka-ops-control-plane
k get nodes
k get pods -A
./scripts/lab.sh check 29
```

</details>
