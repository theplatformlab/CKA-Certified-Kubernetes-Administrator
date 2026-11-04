# Degraded etcd cluster

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` runs a stacked etcd cluster with one member on each control plane node (`{{NODE_CP}}`, `{{NODE_CP2}}`, `{{NODE_CP3}}`, reachable with `ssh <node>`). The cluster still answers requests, but monitoring reports that etcd is degraded.

1. Write the name of the current etcd leader member into `{{WORKDIR}}/etcd-leader.txt` on your exam host.
2. Write the name of the etcd member that is not healthy into `{{WORKDIR}}/etcd-unhealthy.txt` on your exam host.
3. Fix the unhealthy member so that all three etcd members are healthy again. Do not remove or re-add members.

Use the member names as shown by `etcdctl member list`. etcdctl is installed on `{{NODE_CP}}`. The etcd certificates are in `/etc/kubernetes/pki/etcd/`.

## Hints

- `etcdctl endpoint health --cluster` and `etcdctl endpoint status --cluster -w table` check every member listed in `member list`. Both print endpoint URLs, so map them to names with `etcdctl member list -w table`.
- Write the answers before you fix anything: the leader can change while a member restarts. On the broken node, `crictl ps -a --name etcd` and `crictl logs <id>` show why the member keeps exiting.
- The log says `tls: private key does not match public key`. Compare the certificate and key flags in `/etc/kubernetes/manifests/etcd.yaml` with a healthy control plane node.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
export ETCDCTL_API=3 ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
  ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
etcdctl --endpoints=https://127.0.0.1:2379 member list -w table          # ID, NAME, client URL
etcdctl --endpoints=https://127.0.0.1:2379 endpoint health --cluster      # one URL is unhealthy
etcdctl --endpoints=https://127.0.0.1:2379 endpoint status --cluster -w table   # IS LEADER = true
exit
```

Map the URLs to names with the member list, then on the exam host:

```bash
echo <leader-name>    > {{WORKDIR}}/etcd-leader.txt
echo <unhealthy-name> > {{WORKDIR}}/etcd-unhealthy.txt
```

On the unhealthy node (in this session: control plane number {{CP_N}}):

```bash
crictl ps -a --name etcd                 # Exited, restarting
crictl logs $(crictl ps -a --name etcd -q | head -1) 2>&1 | tail -n 3
# ... "listener failed","error":"tls: private key does not match public key"
grep -E -- '--(cert|key|peer-cert|peer-key)-file' /etc/kubernetes/manifests/etcd.yaml
# --key-file=/etc/kubernetes/pki/etcd/peer.key  <- belongs to peer.crt, not server.crt
sed -i 's|--key-file=/etc/kubernetes/pki/etcd/peer.key|--key-file=/etc/kubernetes/pki/etcd/server.key|' \
  /etc/kubernetes/manifests/etcd.yaml
watch crictl ps --name etcd
exit

ssh {{NODE_CP}}
etcdctl --endpoints=https://127.0.0.1:2379 endpoint health --cluster      # 3 x healthy
```

With 3 members the quorum is 2, so the cluster keeps working with one member down. A second failure would stop all writes. etcd needs two certificate pairs: `--cert-file`/`--key-file` for clients (the API server) and `--peer-cert-file`/`--peer-key-file` for the other members. A certificate and key from different pairs fail at startup. The kube-apiserver on the same node only talks to its local etcd, so it was down too and comes back without further changes.
