# API server is down

**Context:** `kubectl config use-context {{CONTEXT}}`

`kubectl` can no longer talk to cluster `{{CLUSTER}}`. The kube-apiserver runs as a static pod on `{{NODE_CP}}` (`ssh {{NODE_CP}}`).

Find the cause and fix it. The API server must be healthy again. Verify the correct value against the configuration on the node, don't guess.

## Hints

- Without an API server, use `crictl ps -a` and `crictl logs` on the control plane node.
- The container logs name what the API server can't load or can't reach: a file, or another component.
- Compare the flag in `/etc/kubernetes/manifests/kube-apiserver.yaml` with what really exists: the files in `/etc/kubernetes/pki/`, or the client URLs etcd listens on in `/etc/kubernetes/manifests/etcd.yaml`. Fix the manifest in place; the kubelet restarts the pod by itself.

## Solution

```bash
k config use-context {{CONTEXT}}
k get nodes                     # connection refused
ssh {{NODE_CP}}
crictl ps -a --name kube-apiserver       # Exited, restarting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -20
```

The logs show one of two faults.

A missing client CA file:

```bash
# ... "command failed" err="open /etc/kubernetes/pki/client-ca.crt: no such file or directory"
ls /etc/kubernetes/pki/                   # ca.crt exists
sed -i 's|--client-ca-file=/etc/kubernetes/pki/client-ca.crt|--client-ca-file=/etc/kubernetes/pki/ca.crt|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

A wrong etcd endpoint:

```bash
# ... addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2397", ...} connect: connection refused
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml        # https://127.0.0.1:2397
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml            # https://127.0.0.1:2379,https://<node-ip>:2379
sed -i 's|--etcd-servers=https://127.0.0.1:2397|--etcd-servers=https://127.0.0.1:2379|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

Then wait for the kubelet to recreate the pod:

```bash
watch crictl ps --name kube-apiserver
exit
k get nodes
```

When the API server is down, `kubectl logs` is useless. Use `crictl logs` on the node, or read `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log`. If the container doesn't even get created (YAML syntax error), the kubelet logs show why: `journalctl -u kubelet | grep apiserver`.

## Pitfalls

- etcd's client port is `2379`; `2380` is the peer port. Take the endpoint from `--listen-client-urls` in `etcd.yaml` instead of typing what you think it is.
- `kubectl apply` of a static pod manifest does nothing useful: edit the file in `/etc/kubernetes/manifests/` in place. If the pod doesn't come back within a minute, `journalctl -u kubelet -f` shows what the kubelet is doing with it.
