# shellcheck shell=bash
# Repair an HA control plane (one kube-apiserver points to a wrong etcd port).
# Sourced by scripts/lab.sh.
LAB_CLUSTER=ha
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
GOOD_ETCD=https://127.0.0.1:2379
BAD_ETCD=https://127.0.0.1:2397

lab_params() {
  echo "CP_N=$(pick 2 3)"
}

_broken() { control_plane_node_n "$CP_N"; }

# _etcdctl <args...> — etcdctl inside the etcd container of the first control plane
# (works without the API server and without etcdctl on the node).
_etcdctl() {
  node_exec "$(control_plane_node)" "crictl exec \$(crictl ps -q --name '^etcd\$' | head -1) etcdctl \
    --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key $*"
}

lab_setup() {
  mkdir -p "$WORKDIR"
  rm -f "$WORKDIR/etcd-members.txt"
  node_exec "$(_broken)" "sed -i 's|- --etcd-servers=$GOOD_ETCD\$|- --etcd-servers=$BAD_ETCD|' $MANIFEST"
}

_readyz() { node_exec "$1" "curl -sk --max-time 5 https://127.0.0.1:6443/readyz | tail -n 1" 2>/dev/null; }

_attempted() {
  [[ -s "$WORKDIR/etcd-members.txt" ]] || [[ "$(_readyz "$(_broken)")" == ok ]]
}

lab_check() {
  local n node ips expected_ips members
  check_gate "Task attempted (API server repaired or etcd-members.txt written)" _attempted
  for n in 1 2 3; do
    node="$(control_plane_node_n "$n")"
    check_eq "kube-apiserver on $node answers /readyz" "$(_readyz "$node")" "ok"
  done
  check_eq "kube-apiserver on $(_broken) uses --etcd-servers=$GOOD_ETCD" \
    "$(node_exec "$(_broken)" "grep -o -- '--etcd-servers=[^ \"]*' $MANIFEST" 2>/dev/null)" "--etcd-servers=$GOOD_ETCD"
  check_eq "Node $(_broken) is Ready" \
    "$(kc --request-timeout=10s get node "$(_broken)" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" "True"
  expected_ips="$(for n in 1 2 3; do
    jp node "$(control_plane_node_n "$n")" '{.status.addresses[?(@.type=="InternalIP")].address}'; echo
  done | sort | xargs)"
  ips="$(jp -n default endpointslice -l kubernetes.io/service-name=kubernetes '{.items[*].endpoints[*].addresses[*]}' \
    | tr ' ' '\n' | sort -u | xargs)"
  check_eq "Service kubernetes has all three API server endpoints" "$ips" "$expected_ips"
  members="$(_etcdctl member list -w simple 2>/dev/null | awk -F', ' '{print $3}' | sort | xargs)"
  check_eq "etcd-members.txt lists the etcd member names" \
    "$(sed 's/[[:space:]]//g; /^$/d' "$WORKDIR/etcd-members.txt" 2>/dev/null | sort | xargs)" "${members:-<etcd unreachable>}"
}

lab_cleanup() {
  local n
  for n in 2 3; do
    node_exec "$(control_plane_node_n "$n")" "sed -i 's|- --etcd-servers=$BAD_ETCD\$|- --etcd-servers=$GOOD_ETCD|' $MANIFEST"
  done
}
