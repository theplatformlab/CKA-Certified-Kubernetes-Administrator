# etcd backup and restore

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` runs etcd as a static pod on `{{NODE_CP}}` (`ssh {{NODE_CP}}`). etcdctl is installed on that node. The last etcd backup was saved to `/opt/cka/etcd-snapshot-previous.db` on `{{NODE_CP}}`. Since then, ConfigMap `app-settings` in namespace `vault-records` was deleted by mistake.

1. Back up the current state of etcd to `/opt/cka/etcd-backup.db` on `{{NODE_CP}}`.
2. Restore the cluster state from `/opt/cka/etcd-snapshot-previous.db`. Restore it into the data directory `/var/lib/etcd-restored` and make etcd use that directory. Keep `/var/lib/etcd` untouched.
3. Make sure the API server serves the restored state (ConfigMap `app-settings` exists again) and the control plane node is `Ready`.

Everything that was created after the previous backup will be lost. That is expected.

## Hints

- Look up the endpoint and certificate paths in `/etc/kubernetes/manifests/etcd.yaml`: `--listen-client-urls`, `--trusted-ca-file`, `--cert-file`, `--key-file`. etcdctl needs them as `--endpoints`, `--cacert`, `--cert` and `--key`.
- `etcdctl snapshot save` talks to the running etcd and needs the certificates. `etcdctl snapshot restore` (or `etcdutl snapshot restore`) only works on files and needs none. Point the `etcd-data` hostPath volume in the etcd manifest to the restored directory.
- The kube-apiserver keeps a cache of the old data. Stop it (and the controller manager and scheduler) while you swap the data directory: move their manifests out of `/etc/kubernetes/manifests/` and back afterwards.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
export ETCDCTL_API=3
grep -E 'listen-client-urls|trusted-ca-file|cert-file|key-file' /etc/kubernetes/manifests/etcd.yaml

# 1. backup of the current state
etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/cka/etcd-backup.db
etcdctl snapshot status /opt/cka/etcd-backup.db -w table

# 2. stop the components that talk to etcd
mkdir -p /root/cp-manifests
mv /etc/kubernetes/manifests/kube-{apiserver,controller-manager,scheduler}.yaml /root/cp-manifests/

# restore into a new data dir and point the etcd static pod at it
etcdctl snapshot restore /opt/cka/etcd-snapshot-previous.db --data-dir /var/lib/etcd-restored
vim /etc/kubernetes/manifests/etcd.yaml
```

```yaml
  volumes:
  - hostPath:
      path: /var/lib/etcd-restored      # was /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

```bash
watch crictl ps --name etcd                  # a new etcd container starts (takes up to a minute)

# 3. start the other components again
mv /root/cp-manifests/*.yaml /etc/kubernetes/manifests/
watch crictl ps                              # kube-apiserver, controller-manager, scheduler running
# controller-manager/scheduler stuck in back-off from earlier restarts? systemctl restart kubelet
exit

k -n vault-records get configmap             # app-settings is back, post-backup-change is gone
k get nodes
```

Only the hostPath has to change. Inside the container etcd still uses `--data-dir=/var/lib/etcd`. If you change `--data-dir` instead, change the `mountPath` too. `snapshot restore` creates a new single-member cluster from the file, so the directory must not exist yet. If you skip stopping the API server, `k get` keeps showing the old state from its watch cache until you restart it. The static pods keep the same pod UID when you move a manifest out and back, so the kubelet also keeps their crash-loop back-off (up to 5 minutes). Restarting the kubelet resets it. Newer etcd versions moved `snapshot restore` and `snapshot status` to `etcdutl`, and `etcdctl` prints a deprecation warning. Both work here.
