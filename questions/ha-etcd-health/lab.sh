# shellcheck shell=bash
# Degraded etcd cluster (one member crashes: its server key doesn't match its
# certificate). Sourced by scripts/lab.sh.
LAB_CLUSTER=ha
MANIFEST=/etc/kubernetes/manifests/etcd.yaml
GOOD_KEY=/etc/kubernetes/pki/etcd/server.key
BAD_KEY=/etc/kubernetes/pki/etcd/peer.key
STATE_DIR=/var/lib/cka-ha-etcd-health

lab_params() {
  echo "CP_N=$(pick 2 3)"       # member that gets broken
  echo "LEAD_N=$(pick 1 2)"     # 1: first control plane leads, 2: the other healthy member leads
}

_broken() { control_plane_node_n "$CP_N"; }

# _etcdctl <args...> — etcdctl inside the etcd container of the first control plane
# (that member is never broken; works without the API server).
_etcdctl() {
  node_exec "$(control_plane_node)" "crictl exec \$(crictl ps -q --name '^etcd\$' | head -1) etcdctl \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key $*"
}

# _member <field> <name> -> ID or client URL of the member named <name>
_member() {
  _etcdctl --endpoints=https://127.0.0.1:2379 member list -w simple 2>/dev/null \
    | awk -F', ' -v n="$2" -v f="$1" '$3 == n { print (f == "id" ? $1 : $5) }'
}

# _leader -> name of the current etcd leader
_leader() {
  local id
  id="$(_etcdctl --endpoints=https://127.0.0.1:2379 endpoint status -w json 2>/dev/null \
    | grep -o '"leader":[0-9]*' | head -1 | cut -d: -f2)"
  [[ -n "$id" ]] || return 1
  _etcdctl --endpoints=https://127.0.0.1:2379 member list -w simple 2>/dev/null \
    | awk -F', ' -v id="$(printf %x "$id")" '$1 == id { print $3 }'
}

lab_setup() {
  local broken healthy target eps i
  broken="$(_broken)"
  mkdir -p "$WORKDIR"
  rm -f "$WORKDIR/etcd-leader.txt" "$WORKDIR/etcd-unhealthy.txt"
  if [[ "$CP_N" == 2 ]]; then healthy="$(control_plane_node_n 3)"; else healthy="$(control_plane_node_n 2)"; fi
  if [[ "$LEAD_N" == 1 ]]; then target="$(control_plane_node)"; else target="$healthy"; fi
  eps="$(_member url "$(control_plane_node)"),$(_member url "$healthy")"

  node_exec "$broken" "sed -i 's|- --key-file=$GOOD_KEY\$|- --key-file=$BAD_KEY|' $MANIFEST"
  echo "  Waiting for the etcd member on $broken to go down ..."
  for (( i = 0; i < 60; i++ )); do
    _etcdctl --endpoints="$(_member url "$broken")" --command-timeout=3s endpoint health >/dev/null 2>&1 || break
    sleep 2
  done
  # Hand leadership to a random healthy member so the leader isn't always the first node.
  if [[ "$(_leader)" != "$target" ]]; then
    _etcdctl --endpoints="$eps" move-leader "$(_member id "$target")" >/dev/null
  fi
  node_exec "$(control_plane_node)" "mkdir -p $STATE_DIR && echo $(_leader) > $STATE_DIR/leader && echo $(_ids) > $STATE_DIR/ids"
}

# _ids -> sorted member IDs (detects members that were removed and re-added)
_ids() {
  _etcdctl --endpoints=https://127.0.0.1:2379 member list -w simple 2>/dev/null | awk -F', ' '{print $1}' | sort | xargs
}

_healthy() { _etcdctl --endpoints=https://127.0.0.1:2379 --command-timeout=5s endpoint health --cluster; }

_attempted() {
  [[ -s "$WORKDIR/etcd-leader.txt" || -s "$WORKDIR/etcd-unhealthy.txt" ]] || _healthy
}

_answer() { tr -d '[:space:]' 2>/dev/null <"$WORKDIR/$1"; }

lab_check() {
  local broken leader_then leader_now got
  broken="$(_broken)"
  leader_then="$(node_exec "$(control_plane_node)" "cat $STATE_DIR/leader" 2>/dev/null)"
  leader_now="$(_leader)"
  check_gate "Task attempted (etcd repaired or answer files written)" _attempted
  got="$(_answer etcd-leader.txt)"
  if [[ -n "$got" && ( "$got" == "$leader_then" || "$got" == "$leader_now" ) ]]; then
    _pass "etcd-leader.txt names the leader ($leader_then)"
  else
    _fail "etcd-leader.txt names the leader ($leader_then)" "got '${got:-<empty>}'"
  fi
  check_eq "etcd-unhealthy.txt names the unhealthy member" "$(_answer etcd-unhealthy.txt)" "$broken"
  check "All three etcd members are healthy" _healthy
  check_eq "etcd on $broken uses --key-file=$GOOD_KEY" \
    "$(node_exec "$broken" "grep -o -- '--key-file=[^ \"]*' $MANIFEST" 2>/dev/null)" "--key-file=$GOOD_KEY"
  check_eq "etcd members are unchanged (none removed or re-added)" \
    "$(_ids)" "$(node_exec "$(control_plane_node)" "cat $STATE_DIR/ids" 2>/dev/null)"
  check_eq "kube-apiserver on $broken answers /readyz" \
    "$(node_exec "$broken" "curl -sk --max-time 5 https://127.0.0.1:6443/readyz | tail -n 1" 2>/dev/null)" "ok"
}

lab_cleanup() {
  local n
  for n in 2 3; do
    node_exec "$(control_plane_node_n "$n")" "sed -i 's|- --key-file=$BAD_KEY\$|- --key-file=$GOOD_KEY|' $MANIFEST"
  done
  node_exec "$(control_plane_node)" "rm -rf $STATE_DIR"
}
