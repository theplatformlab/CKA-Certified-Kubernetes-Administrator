# Exercise 09 — kubeadm Cluster Upgrade

> Related: [README — Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25)

Upgrade a cluster from one minor version to the next using kubeadm. The CKA frequently asks this — you need to know the exact sequence.

## Tasks

This exercise runs on the ops cluster (`./scripts/init-cluster.sh --profile ops`, `./scripts/lab.sh setup 09` confirms it is ready). The cluster runs Kubernetes v1.35.x on two nodes, `cka-ops-control-plane` and `cka-ops-worker`. Every node has the `pkgs.k8s.io` apt repository for v1.36 configured. Open a shell on a node with `docker exec -it <node> bash` — the kind equivalent of `ssh <node>` in the exam. You are root on the nodes, so `sudo` is not needed. Run `kubectl` (drain/uncordon/get nodes) from your own terminal.

Upgrade the whole cluster to the **latest v1.36 patch release available in the apt repository** (`apt-cache madison kubeadm`), control plane first, then the worker.

1. Check the current cluster version (`k get nodes`, `kubeadm version` on a node)
2. Upgrade the control plane node `cka-ops-control-plane`:
   a. Update the kubeadm package to the target version
   b. Run `kubeadm upgrade plan` to see available upgrades
   c. Run `kubeadm upgrade apply v1.36.x`
   d. Upgrade kubelet and kubectl packages
   e. Restart kubelet
3. Upgrade the worker node `cka-ops-worker`:
   a. Drain the worker node
   b. Update the kubeadm package on the worker
   c. Run `kubeadm upgrade node`
   d. Update kubelet and kubectl packages, restart kubelet
   e. Uncordon the worker
4. Verify all nodes show the new version, are `Ready` and schedulable

Validate with `./scripts/lab.sh check 09`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Always upgrade control plane first, then workers one at a time
- The package manager commands depend on your OS (apt for Ubuntu, yum for CentOS)
- `kubeadm upgrade plan` shows you what versions are available
- On workers, it's `kubeadm upgrade node` (NOT `kubeadm upgrade apply`)
- Don't forget to drain before upgrading a worker
- `apt-get install kubelet` may ask about `/etc/default/kubelet`: keep your currently-installed version (`N`, the default) — it holds the node's kubelet flags
- With a single worker, draining it evicts CoreDNS too (the control plane is tainted): DNS is down until you uncordon

</details>

## What tripped me up

> After upgrading kubelet, it didn't start. I ran `systemctl restart kubelet` but forgot `systemctl daemon-reload` first. The systemd unit file changed but systemd didn't know about it. Always `daemon-reload` then `restart`. In that order. I lost 4 minutes on this during practice.
>
> On the worker node, I ran `kubeadm upgrade apply` instead of `kubeadm upgrade node`. Apply is for the control plane only. On workers it's `kubeadm upgrade node`. The error message is confusing — it doesn't immediately say "wrong command." It tries to run and fails partway through.
>
> Also: drain the worker BEFORE upgrading it. I upgraded first, then drained, and some pods got killed mid-upgrade when the node restarted. The safe order is: drain → upgrade → restart kubelet → uncordon.

## Verify

```bash
./scripts/lab.sh check 09
```

Manual checks:

```bash
# All nodes should show the new version, Ready, no SchedulingDisabled
k get nodes

# Control plane components run the new version
k -n kube-system get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image

# Binaries on each node should match
docker exec cka-ops-control-plane kubeadm version -o short
docker exec cka-ops-worker kubelet --version
docker exec cka-ops-worker kubectl version --client
```

## Cleanup

No cleanup possible — this is a one-way upgrade. To practise again, recreate the cluster:

```bash
./scripts/init-cluster.sh --profile ops --recreate
```

<details>
<summary>Solution</summary>

The commands below use `1.36.6`, the latest patch at the time of writing — use whatever `apt-cache madison kubeadm` shows as the newest.

```bash
# === CONTROL PLANE NODE ===

# Check current version
k get nodes

# Shell on the control plane (exam: ssh cka-ops-control-plane)
docker exec -it cka-ops-control-plane bash
kubeadm version -o short

# Find the target version
apt-get update
apt-cache madison kubeadm | head -3

# Update kubeadm
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.36.6-1.1
apt-mark hold kubeadm
kubeadm version -o short          # v1.36.6

# Plan
kubeadm upgrade plan

# Apply
kubeadm upgrade apply v1.36.6     # confirm with y

# Update kubelet + kubectl (keep the current /etc/default/kubelet when asked)
apt-mark unhold kubelet kubectl
apt-get install -y -o Dpkg::Options::=--force-confold kubelet=1.36.6-1.1 kubectl=1.36.6-1.1
apt-mark hold kubelet kubectl

# Restart kubelet
systemctl daemon-reload
systemctl restart kubelet
exit

# Verify control plane
k get nodes                       # cka-ops-control-plane   Ready   v1.36.6

# === WORKER NODE ===

# From your terminal: drain worker
k drain cka-ops-worker --ignore-daemonsets --delete-emptydir-data

# Shell on the worker (exam: ssh cka-ops-worker)
docker exec -it cka-ops-worker bash

# Update kubeadm on worker
apt-get update
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.36.6-1.1
apt-mark hold kubeadm

# Upgrade node config
kubeadm upgrade node

# Update kubelet + kubectl
apt-mark unhold kubelet kubectl
apt-get install -y -o Dpkg::Options::=--force-confold kubelet=1.36.6-1.1 kubectl=1.36.6-1.1
apt-mark hold kubelet kubectl

# Restart kubelet
systemctl daemon-reload
systemctl restart kubelet

# Exit back to your terminal
exit

# Uncordon worker
k uncordon cka-ops-worker

# Verify
k get nodes
./scripts/lab.sh check 09
```

On a real kubeadm node you are not root: prefix the node commands with `sudo`.

Remember:
- Control plane: `kubeadm upgrade apply`
- Worker: `kubeadm upgrade node`
- Always drain workers before upgrading them
- Always uncordon after

</details>
