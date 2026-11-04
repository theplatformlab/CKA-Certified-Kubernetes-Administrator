# Upgrade the cluster with kubeadm

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` runs Kubernetes v1.35 on the control plane node `{{NODE_CP}}` and the worker node `{{NODE_W1}}`. Both nodes are reachable with `ssh <node>`, and the Kubernetes apt repository for v1.36 is already configured on them.

Upgrade the whole cluster to the latest v1.36 patch release available in that apt repository, control plane first, then the worker:

1. On both nodes, `kubeadm`, `kubelet` and `kubectl` must have the target version.
2. The control plane components and kube-proxy must run the target version.
3. Afterwards both nodes must be `Ready` and schedulable.

## Hints

- `apt-cache madison kubeadm` lists the versions the repository offers. If apt refuses to change a package, it is on hold: `apt-mark unhold` before installing, `apt-mark hold` afterwards.
- Upgrade `kubeadm` first, then let it upgrade the node: `kubeadm upgrade plan` and `kubeadm upgrade apply v1.36.x` on the control plane, `kubeadm upgrade node` on the worker. Only then upgrade `kubelet` and `kubectl`.
- Drain the worker before you upgrade it and uncordon it afterwards. After installing the new kubelet: `systemctl daemon-reload && systemctl restart kubelet`.

## Solution

Replace `1.36.6` with the newest version `apt-cache madison kubeadm` shows.

```bash
k config use-context {{CONTEXT}}
k get nodes                                   # both on v1.35.x

# === control plane ===
ssh {{NODE_CP}}
apt-get update
apt-cache madison kubeadm | head -3           # newest: 1.36.6-1.1

apt-mark unhold kubeadm
apt-get install -y kubeadm=1.36.6-1.1
apt-mark hold kubeadm
kubeadm version -o short                      # v1.36.6

kubeadm upgrade plan
kubeadm upgrade apply v1.36.6 -y

# keep the current /etc/default/kubelet when apt asks (--force-confold)
apt-mark unhold kubelet kubectl
apt-get install -y -o Dpkg::Options::=--force-confold kubelet=1.36.6-1.1 kubectl=1.36.6-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
exit

k get nodes                                   # {{NODE_CP}} v1.36.6

# === worker ===
k drain {{NODE_W1}} --ignore-daemonsets --delete-emptydir-data

ssh {{NODE_W1}}
apt-get update
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.36.6-1.1
apt-mark hold kubeadm
kubeadm upgrade node

apt-mark unhold kubelet kubectl
apt-get install -y -o Dpkg::Options::=--force-confold kubelet=1.36.6-1.1 kubectl=1.36.6-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet
exit

k uncordon {{NODE_W1}}
k get nodes                                   # both Ready, v1.36.6
```

On a real kubeadm node you are not root: prefix the node commands with `sudo`.

## Pitfalls

- After installing the new kubelet package it doesn't come up without `systemctl daemon-reload` before `systemctl restart kubelet`, in that order.
- `kubeadm upgrade apply` is for the first control plane node only. On workers (and further control plane nodes) it's `kubeadm upgrade node`; `apply` on a worker fails halfway with a confusing error.
- Drain the worker before the upgrade, not after. With a single worker, draining it also evicts CoreDNS (the control plane is tainted), so DNS is down until you uncordon.
