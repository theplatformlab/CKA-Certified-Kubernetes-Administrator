# Join a worker node with kubeadm

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` was created with kubeadm. A new machine `{{CLUSTER}}-{{JOIN_NAME}}` has been prepared for it: containerd is running and `kubeadm`, `kubelet` and `kubectl` are installed, but it is not part of the cluster yet. Both nodes are reachable with `ssh <node>`.

1. Join `{{CLUSTER}}-{{JOIN_NAME}}` to the cluster as a worker node using kubeadm. The node must be `Ready` with the name `{{CLUSTER}}-{{JOIN_NAME}}`.
2. Label the node with `pool={{POOL}}`.

Environment note: kubeadm prints a preflight warning about swap on this machine. You can ignore it.

## Hints

- A worker joins with `kubeadm join <api-server>:6443 --token ... --discovery-token-ca-cert-hash sha256:...`. The control plane can create that command for you.
- Bootstrap tokens expire (24 h by default), so create a fresh one on the control plane node: `kubeadm token create --print-join-command`.
- `ssh {{NODE_CP}}`, run `kubeadm token create --print-join-command`, copy the output, `ssh {{CLUSTER}}-{{JOIN_NAME}}` and run it there as root. Then `k get nodes -w` and `k label node`.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
kubeadm token create --print-join-command
# kubeadm join {{NODE_CP}}:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:...
exit

ssh {{CLUSTER}}-{{JOIN_NAME}}
kubeadm join {{NODE_CP}}:6443 --token abcdef.0123456789abcdef --discovery-token-ca-cert-hash sha256:...
# [WARNING Swap]: ...
# This node has joined the cluster
systemctl is-enabled kubelet                 # enabled
exit

k get nodes -w                               # {{CLUSTER}}-{{JOIN_NAME}} NotReady -> Ready
k label node {{CLUSTER}}-{{JOIN_NAME}} pool={{POOL}}
```

`kubeadm join` discovers the cluster with the token and verifies the API server against the CA hash. It then downloads the cluster-wide kubelet configuration (ConfigMap `kubelet-config` in `kube-system`), writes `/var/lib/kubelet/config.yaml` and starts the kubelet, which gets its client certificate through a CSR that is approved automatically. The node becomes `Ready` once the CNI DaemonSet (kindnet here) and kube-proxy are running on it. The node name defaults to the hostname. `--node-name` overrides it.
