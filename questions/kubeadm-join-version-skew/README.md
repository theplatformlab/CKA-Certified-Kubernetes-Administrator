# Join a node with an outdated kubelet

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` was created with kubeadm. A machine `{{CLUSTER}}-{{JOIN_NAME}}` was set up from an old provisioning template: containerd is running and `kubeadm`, `kubelet` and `kubectl` are installed from the Kubernetes apt repository, but `kubelet` and `kubectl` are one minor version behind the control plane. Both nodes are reachable with `ssh <node>`.

1. Bring `kubelet` and `kubectl` on `{{CLUSTER}}-{{JOIN_NAME}}` to exactly the version the control plane runs, using apt. The apt repository for that minor version is already configured on the machine.
2. Join `{{CLUSTER}}-{{JOIN_NAME}}` to the cluster as a worker node using kubeadm. The node must be `Ready` with the name `{{CLUSTER}}-{{JOIN_NAME}}`.

Environment note: kubeadm prints a preflight warning about swap on this machine. You can ignore it.

## Hints

- `k get nodes` and `k version` show the control plane version. On the new machine, `kubelet --version`, `kubectl version --client` and `kubeadm version` show what is installed.
- `apt-cache madison kubelet` lists the versions the repository offers; pick the one that matches the control plane, not the newest. If apt refuses to change the packages, check `apt-mark showhold`.
- `apt-mark unhold kubelet kubectl`, `apt-get install kubelet=<version> kubectl=<version>`, `apt-mark hold ...`. Then get a join command with `kubeadm token create --print-join-command` on the control plane node.

## Solution

```bash
k config use-context {{CONTEXT}}
k get nodes                                  # control plane on v1.35.1

ssh {{CLUSTER}}-{{JOIN_NAME}}
kubelet --version                            # Kubernetes v1.34.x
kubeadm version -o short                     # v1.35.1
cat /etc/apt/sources.list.d/kubernetes.list  # .../core:/stable:/v1.35/deb/ /
apt-mark showhold                            # kubectl, kubelet
apt-get update
apt-cache madison kubelet | grep 1.35.1      # 1.35.1-1.1
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.1-1.1 kubectl=1.35.1-1.1
apt-mark hold kubelet kubectl
kubelet --version; kubectl version --client  # v1.35.1
exit

ssh {{NODE_CP}}
kubeadm token create --print-join-command
# kubeadm join {{NODE_CP}}:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:...
exit

ssh {{CLUSTER}}-{{JOIN_NAME}}
kubeadm join {{NODE_CP}}:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:...
# [WARNING Swap]: ...
# This node has joined the cluster
exit

k get nodes -w                               # {{CLUSTER}}-{{JOIN_NAME}} Ready, VERSION v1.35.1
```

kubeadm does not stop you here: a kubelet may be up to three minor versions older than the API server, so the join works with the old kubelet too and the node then shows the old version in `k get nodes`. Matching versions are still what you want on a new node (and what `kubeadm upgrade` expects later). Kubernetes packages are usually held (`apt-mark hold`) so a routine `apt-get upgrade` can't move them; unhold them for the change and hold them again afterwards. The pkgs.k8s.io repositories are per minor version (`/core:/stable:/v1.35/deb/`), so one repository offers every patch release of that minor. If you upgrade the kubelet after the join instead, restart it (`systemctl restart kubelet`) so the node reports the new version.
