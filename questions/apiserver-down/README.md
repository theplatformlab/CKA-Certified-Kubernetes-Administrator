# API server is down

**Context:** `kubectl config use-context {{CONTEXT}}`

`kubectl` can no longer talk to cluster `{{CLUSTER}}`. The kube-apiserver runs as a static pod on `{{NODE_CP}}` (`ssh {{NODE_CP}}`).

Find the cause and fix it. The API server must be healthy again.

## Hints

- Without an API server, use `crictl ps -a` and `crictl logs` on the control plane node.
- The container logs name the file the API server can't load.
- Fix the path in `/etc/kubernetes/manifests/kube-apiserver.yaml`; the kubelet restarts the pod by itself.

## Solution

```bash
k config use-context {{CONTEXT}}
k get nodes                     # connection refused
ssh {{NODE_CP}}
crictl ps -a --name kube-apiserver       # Exited, restarting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1)
# ... unable to load client CA provider: open /etc/kubernetes/pki/client-ca.crt: no such file or directory

ls /etc/kubernetes/pki/                   # ca.crt exists
sed -i 's|--client-ca-file=/etc/kubernetes/pki/client-ca.crt|--client-ca-file=/etc/kubernetes/pki/ca.crt|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
watch crictl ps --name kube-apiserver
exit
k get nodes
```

When the API server is down, `kubectl logs` is useless. Use `crictl logs` on the node, or read `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log`. If the container doesn't even get created (YAML syntax error), the kubelet logs show why: `journalctl -u kubelet | grep apiserver`.
