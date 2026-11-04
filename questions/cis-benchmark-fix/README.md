# Fix CIS benchmark findings with kube-bench

**Context:** `kubectl config use-context {{CONTEXT}}`

`kube-bench` is installed on both nodes of cluster `{{CLUSTER}}`. Fix the following findings of the CIS Kubernetes Benchmark. Leave the other findings as they are.

On the control plane node `{{NODE_CP}}` (`ssh {{NODE_CP}}`, `kube-bench run --targets master`):

- **1.1.7** Ensure that the etcd pod specification file permissions are set to 600 or more restrictive
- **1.2.15** Ensure that the `--profiling` argument of the kube-apiserver is set to false
- **1.3.2** Ensure that the `--profiling` argument of the kube-controller-manager is set to false

On the worker node `{{NODE_W1}}` (`ssh {{NODE_W1}}`, `kube-bench run --targets node`):

- **4.2.1** Ensure that the kubelet's anonymous authentication is disabled
- **4.2.2** Ensure that the kubelet's authorization mode is not `AlwaysAllow` (use `Webhook`)

All control plane components must be running again, and both nodes must be `Ready`.

## Hints

- `kube-bench run --targets master --check 1.2.15` runs a single check. Every failed check is followed by a remediation text at the end of the output.
- The control plane components are static Pods: edit their manifests in `/etc/kubernetes/manifests`, and the kubelet restarts them.
- The kubelet on a kubeadm node reads its settings from the file given with `--config` (see `systemctl cat kubelet`). The fields are `authentication.anonymous.enabled` and `authorization.mode`. Restart the kubelet afterwards.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
kube-bench run --targets master | grep FAIL
chmod 600 /etc/kubernetes/manifests/etcd.yaml                          # 1.1.7
vim /etc/kubernetes/manifests/kube-apiserver.yaml                      # 1.2.15: add  - --profiling=false
vim /etc/kubernetes/manifests/kube-controller-manager.yaml             # 1.3.2:  add  - --profiling=false
watch crictl ps                    # wait until kube-apiserver and kube-controller-manager are running again
kube-bench run --targets master --check 1.1.7,1.2.15,1.3.2
exit

ssh {{NODE_W1}}
kube-bench run --targets node | grep FAIL
vim /var/lib/kubelet/config.yaml
```

```yaml
authentication:
  anonymous:
    enabled: false          # 4.2.1
  # ...
authorization:
  mode: Webhook             # 4.2.2
```

```bash
systemctl restart kubelet
kube-bench run --targets node --check 4.2.1,4.2.2
exit
k get nodes
```

Don't copy manifests into `/etc/kubernetes/manifests` as backups: the kubelet runs every file there as a static Pod. Keep them in `/root` or similar. With profiling enabled, anyone allowed to call `/debug/pprof` can read performance data of the component. With `AlwaysAllow`, every authenticated request to the kubelet API (port 10250) is allowed, and with anonymous auth on top of that, any request without credentials is too. That includes `exec` into Pods. kube-bench reads the flags of the running processes and the config files, so its result only changes after the components restart.
