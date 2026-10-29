# shellcheck shell=bash
# Tune the kubelet configuration of a worker (maxPods, hard eviction threshold).
# Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
CONFIG=/var/lib/kubelet/config.yaml
BACKUP=/root/cka-kubelet-config.yaml.orig

lab_params() {
  echo "MAX_PODS=$(pick 40 50 60 75 80)"
  echo "MEM_EVICT=$(pick 150Mi 200Mi 250Mi 300Mi)"
}

lab_setup() {
  node_exec "$(worker_node 1)" "[ -f $BACKUP ] || cp $CONFIG $BACKUP"
}

# _configz -> the configuration the running kubelet uses (JSON, via the API server)
_configz() { kc --request-timeout=10s get --raw "/api/v1/nodes/$(worker_node 1)/proxy/configz" 2>/dev/null; }

# _json_value <json> <key> -> value of the first "key":value pair (string quotes removed)
_json_value() { grep -o "\"$2\":\"\\{0,1\\}[^\",}]*" <<<"$1" | head -1 | sed 's/.*://; s/"//g'; }

lab_check() {
  local node cz; node="$(worker_node 1)"
  cz="$(_configz)"
  check_gate "$CONFIG was changed" node_exec "$node" "! cmp -s $CONFIG $BACKUP"
  check_eq "kubelet on $node runs with maxPods $MAX_PODS" "$(_json_value "$cz" maxPods)" "$MAX_PODS"
  check_eq "kubelet on $node runs with evictionHard memory.available $MEM_EVICT" \
    "$(_json_value "$cz" memory.available)" "$MEM_EVICT"
  check_eq "The other evictionHard thresholds are kept (nodefs.available, imagefs.available, nodefs.inodesFree 0%)" \
    "$(_json_value "$cz" nodefs.available) $(_json_value "$cz" imagefs.available) $(_json_value "$cz" nodefs.inodesFree)" "0% 0% 0%"
  check_eq "$CONFIG has maxPods: $MAX_PODS" \
    "$(node_exec "$node" "sed -n 's/^maxPods: *//p' $CONFIG" 2>/dev/null)" "$MAX_PODS"
  check_eq "Node $node reports $MAX_PODS allocatable pods" "$(jp node "$node" '{.status.allocatable.pods}')" "$MAX_PODS"
  check_eq "Node $node is Ready" "$(jp node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "kubelet service is active" "$(node_exec "$node" "systemctl is-active kubelet" 2>/dev/null)" "active"
}

lab_cleanup() {
  node_exec "$(worker_node 1)" "
    if [ -f $BACKUP ]; then
      cp $BACKUP $CONFIG && rm $BACKUP
      systemctl restart kubelet
    fi
  "
}
