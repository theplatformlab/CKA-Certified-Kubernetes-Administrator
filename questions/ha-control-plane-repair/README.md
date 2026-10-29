# Repair an HA control plane

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` has a highly-available control plane: three control plane nodes `{{NODE_CP}}`, `{{NODE_CP2}}` and `{{NODE_CP3}}` with stacked etcd, behind a load balancer. All nodes are reachable with `ssh <node>`. Monitoring reports that the control plane is not fully redundant any more.

1. Find the control plane node whose kube-apiserver is not healthy and fix it. Do not change the other control plane nodes.
2. Write the names of all etcd members, as reported by `etcdctl member list`, into `{{WORKDIR}}/etcd-members.txt` on your exam host, one name per line.
3. Make sure that the `kubernetes` Service in namespace `default` lists the addresses of all three API servers as endpoints.

etcdctl is installed on `{{NODE_CP}}`. The etcd certificates are in `/etc/kubernetes/pki/etcd/`.

## Hints

- `kubectl` still works because the load balancer only forwards to healthy API servers. Compare `k get nodes` and `k get endpointslice -l kubernetes.io/service-name=kubernetes` with the list of control plane IPs.
- On every control plane node, `curl -k https://127.0.0.1:6443/readyz` tells you whether its API server is up. On the broken node, `crictl ps -a --name kube-apiserver` and `crictl logs <id>` show why it keeps restarting.
- In a stacked etcd setup every kube-apiserver talks to the etcd member on its own node at `https://127.0.0.1:2379`. Compare `--etcd-servers` in `/etc/kubernetes/manifests/kube-apiserver.yaml` with a healthy node.

## Solution

```bash
k config use-context {{CONTEXT}}
k get endpointslice -l kubernetes.io/service-name=kubernetes    # only 2 addresses
k get nodes -o wide                      # the control plane IPs
ssh {{NODE_CP}}
curl -sk https://127.0.0.1:6443/readyz   # ok -- repeat on {{NODE_CP2}} and {{NODE_CP3}}
exit
```

The node that doesn't answer `ok` is the broken one (in this session: control plane number {{CP_N}}). `ssh` to it:

```bash
crictl ps -a --name kube-apiserver       # Exited, restart count growing
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | grep -m1 dial
# ... Error while dialing: dial tcp 127.0.0.1:2397: connect: connection refused
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
sed -i 's|--etcd-servers=https://127.0.0.1:2397|--etcd-servers=https://127.0.0.1:2379|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
watch crictl ps --name kube-apiserver
curl -sk https://127.0.0.1:6443/readyz   # ok
exit
```

etcd members (on `{{NODE_CP}}`):

```bash
ssh {{NODE_CP}}
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table
exit
printf '%s\n' {{NODE_CP}} {{NODE_CP2}} {{NODE_CP3}} > {{WORKDIR}}/etcd-members.txt   # the NAME column

k get endpointslice -l kubernetes.io/service-name=kubernetes   # 3 addresses again
k get nodes
```

The cluster kept working because the load balancer health-checks `/healthz` and etcd still had quorum. That is the point of HA, and also why a broken member goes unnoticed. Each API server adds its own address to the `kubernetes` endpoints through a lease, so a missing address is a quick way to spot a dead API server. kubeadm names etcd members after the node, but read them from `member list` instead of assuming that.
