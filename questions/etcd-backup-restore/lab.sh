# shellcheck shell=bash
# etcd backup and restore. Setup takes a snapshot (the "last backup"), then
# changes the cluster; the user backs up the current state and restores the old one.
# Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
NS=vault-records
MANIFEST=/etc/kubernetes/manifests/etcd.yaml
OLD_SNAP=/opt/cka/etcd-snapshot-previous.db
NEW_SNAP=/opt/cka/etcd-backup.db
RESTORE_DIR=/var/lib/etcd-restored
STATE_DIR=/var/lib/cka-etcd-backup-restore

lab_params() {
  echo "TOKEN=$(rand_suffix 8)"
}

# _etcdctl <args...> — etcdctl inside the running etcd container (no etcdctl needed on the node)
_etcdctl() {
  node_exec "$(control_plane_node)" "crictl exec \$(crictl ps -q --name '^etcd\$' | head -1) etcdctl \
    --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key $*"
}

# _data_dir -> hostPath of the etcd-data volume in the etcd manifest
_data_dir() {
  node_exec "$(control_plane_node)" "grep -B3 'name: etcd-data' $MANIFEST | sed -n 's/^ *path: *//p'" 2>/dev/null | tail -1
}

lab_setup() {
  local cp; cp="$(control_plane_node)"
  if [[ "$(_data_dir)" != /var/lib/etcd ]]; then
    log_error "etcd does not use /var/lib/etcd (left over from a previous run?). Run cleanup first."
    return 1
  fi
  ensure_ns "$NS"
  kc -n "$NS" delete configmap post-backup-change --ignore-not-found >/dev/null
  kc -n "$NS" create configmap app-settings --from-literal=token="$TOKEN" --from-literal=mode=production \
    --dry-run=client -o yaml | kc apply -f -
  # The "last backup": taken inside the etcd container, written to the node's /opt/cka.
  node_exec "$cp" "mkdir -p /opt/cka $STATE_DIR && rm -f $OLD_SNAP $NEW_SNAP && rm -rf $RESTORE_DIR && cp $MANIFEST $STATE_DIR/etcd.yaml"
  _etcdctl snapshot save /var/lib/etcd/cka-snapshot.db >/dev/null 2>&1
  node_exec "$cp" "mv /var/lib/etcd/cka-snapshot.db $OLD_SNAP"
  node_exec "$cp" "etcdctl --write-out=simple snapshot status $OLD_SNAP 2>/dev/null | awk -F', ' '{print \$2}' > $STATE_DIR/old-revision"
  # Changes after the backup.
  kc -n "$NS" delete configmap app-settings
  kc -n "$NS" create configmap post-backup-change --from-literal=note="created after the last backup"
}

_rev() { node_exec "$(control_plane_node)" "etcdctl --write-out=simple snapshot status $1 2>/dev/null | awk -F', ' '{print \$2}'" 2>/dev/null; }

_attempted() {
  node_exec "$(control_plane_node)" "test -e $NEW_SNAP" 2>/dev/null || [[ "$(_data_dir)" != /var/lib/etcd ]]
}

lab_check() {
  local cp old new cms; cp="$(control_plane_node)"
  old="$(node_exec "$cp" "cat $STATE_DIR/old-revision" 2>/dev/null)"
  new="$(_rev "$NEW_SNAP")"
  check_gate "Task attempted ($NEW_SNAP exists or etcd data dir changed)" _attempted
  check_match "$NEW_SNAP is a valid etcd snapshot" "$new" '^[0-9]+$'
  check "$NEW_SNAP was taken after the previous backup (revision $new > $old)" test "${new:-0}" -gt "${old:-0}"
  check_eq "etcd data volume (hostPath) is $RESTORE_DIR" "$(_data_dir)" "$RESTORE_DIR"
  check "$RESTORE_DIR contains a restored etcd member" node_exec "$cp" "test -d $RESTORE_DIR/member/snap"
  check_eq "API server answers /readyz" "$(kc --request-timeout=10s get --raw /readyz 2>/dev/null)" "ok"
  check_eq "ConfigMap app-settings is back (token $TOKEN)" "$(jp -n $NS configmap app-settings '{.data.token}')" "$TOKEN"
  cms="$(jp -n $NS configmap '{.items[*].metadata.name}')"
  if [[ -n "$cms" && "$cms" != *post-backup-change* ]]; then
    _pass "ConfigMap post-backup-change is gone (state of the previous backup)"
  else
    _fail "ConfigMap post-backup-change is gone (state of the previous backup)" "ConfigMaps in $NS: '${cms:-<none/API error>}'"
  fi
  check_eq "Node $cp is Ready" \
    "$(kc --request-timeout=10s get node "$cp" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" "True"
}

lab_cleanup() {
  local cp i; cp="$(control_plane_node)"
  if node_exec "$cp" "test -f $STATE_DIR/etcd.yaml && ! cmp -s $STATE_DIR/etcd.yaml $MANIFEST"; then
    echo "  Restoring the original etcd manifest (data dir /var/lib/etcd) ..."
    node_exec "$cp" "
      cp $STATE_DIR/etcd.yaml /root/etcd.yaml.cka && mv /root/etcd.yaml.cka $MANIFEST
      for i in \$(seq 1 90); do
        crictl inspect \$(crictl ps -q --name '^etcd\$' | head -1) 2>/dev/null | grep -q '\"host_path\": \"/var/lib/etcd\"' && break
        sleep 2
      done
      # The other components cached the restored (older) state: restart them. Restarting the
      # kubelet as well resets its crash-loop back-off, so they come back right away.
      for c in kube-apiserver kube-controller-manager kube-scheduler; do
        crictl stop \$(crictl ps -q --name \$c) >/dev/null 2>&1
      done
      systemctl restart kubelet
    "
    for (( i = 0; i < 90; i++ )); do kc --request-timeout=5s get --raw /readyz >/dev/null 2>&1 && break; sleep 2; done
  fi
  node_exec "$cp" "rm -rf $RESTORE_DIR $STATE_DIR $OLD_SNAP $NEW_SNAP"
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
