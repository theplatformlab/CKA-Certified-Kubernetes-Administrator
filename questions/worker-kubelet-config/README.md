# Worker node NotReady

**Context:** `kubectl config use-context {{CONTEXT}}`

Node `{{NODE_W1}}` is `NotReady`. Access it with `ssh {{NODE_W1}}`.

Find the cause and fix it so that the node is `Ready` again. Fix the configuration, do not work around it: don't create, copy or rename files under `/etc/kubernetes/`. The fix must survive a reboot of the node.

## Hints

- `systemctl status kubelet` and `journalctl -u kubelet -n 30 --no-pager` on the node. Read the error closely: which file is the kubelet really looking for, and why?
- The kubelet only falls back to the bootstrap kubeconfig when the file given in `--kubeconfig` doesn't exist. Compare the kubelet's flags (`systemctl cat kubelet`, `ps -ef | grep kubelet`) with the files in `/etc/kubernetes/`.
- The flags come from the systemd drop-in `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`. After editing a unit file, systemd needs `systemctl daemon-reload` before the restart.

## Solution

```bash
k config use-context {{CONTEXT}}
k get nodes                                   # {{NODE_W1}} NotReady
ssh {{NODE_W1}}

systemctl status kubelet                      # activating (auto-restart)
journalctl -u kubelet -n 20 --no-pager
# ... unable to load bootstrap kubeconfig: stat /etc/kubernetes/bootstrap-kubelet.conf: no such file or directory

systemctl cat kubelet | grep kubeconfig
# --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.config
ls /etc/kubernetes/                           # kubelet.conf  manifests  pki

sed -i 's|--kubeconfig=/etc/kubernetes/kubelet.config|--kubeconfig=/etc/kubernetes/kubelet.conf|' \
  /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl restart kubelet
systemctl status kubelet                      # active (running)
exit

k get nodes -w
```

The error message is misleading on purpose: the kubelet couldn't find the file given in `--kubeconfig`, so it tried to bootstrap a new client certificate. The bootstrap kubeconfig is deleted after `kubeadm join`, so that failed too. Without `systemctl daemon-reload` the restart still uses the old unit definition, and nothing changes.
