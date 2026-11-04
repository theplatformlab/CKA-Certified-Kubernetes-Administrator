# Kubelet and container runtime

**Context:** `kubectl config use-context {{CONTEXT}}`

Node `{{NODE_W1}}` is `NotReady`. Access it with `ssh {{NODE_W1}}`.

Fix the node so that it is `Ready` again. The kubelet must use containerd at `unix:///run/containerd/containerd.sock`, and it must be enabled to start automatically when the node boots.

## Hints

- `ssh` to the node and look at `systemctl status kubelet` and `journalctl -u kubelet`.
- The runtime endpoint can be set in `/var/lib/kubelet/config.yaml`, `/var/lib/kubelet/kubeadm-flags.env` or `/etc/default/kubelet`.
- "Starts on boot" means `systemctl enable`. Restart the kubelet after the fix.

## Solution

```bash
k config use-context {{CONTEXT}}
k get nodes                                  # {{NODE_W1}} NotReady
ssh {{NODE_W1}}

systemctl status kubelet                     # activating (auto-restart), disabled
journalctl -u kubelet -n 20 --no-pager       # ... endpoint "unix:///run/cri-dockerd.sock": no such file

grep -rn cri-dockerd /var/lib/kubelet/config.yaml /var/lib/kubelet/kubeadm-flags.env /etc/default/kubelet 2>/dev/null
sed -i 's|unix:///run/cri-dockerd.sock|unix:///run/containerd/containerd.sock|' /var/lib/kubelet/config.yaml
systemctl enable --now kubelet
systemctl restart kubelet
exit

k get nodes -w
```

Runtime settings can live in three places: `/var/lib/kubelet/config.yaml` (`containerRuntimeEndpoint`), `/var/lib/kubelet/kubeadm-flags.env` (`--container-runtime-endpoint`) and `/etc/default/kubelet`. Check all three. "Starts on boot" means `systemctl enable`.
