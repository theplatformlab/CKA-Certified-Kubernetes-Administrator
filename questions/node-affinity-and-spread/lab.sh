# shellcheck shell=bash
# Required node affinity + topology spread constraints. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=edge

lab_params() {
  echo "POOL=$(pick edge ingress frontend gateway)"
  echo "REPLICAS=$(pick 4 6)"
}

lab_setup() {
  ensure_ns "$NS"
  kc label node "$(worker_node 1)" "node-pool=$POOL" --overwrite >/dev/null
  kc label node "$(worker_node 2)" "node-pool=$POOL" --overwrite >/dev/null
}

_t='{.spec.template.spec'

lab_check() {
  local w1 w2; w1="$(worker_node 1)"; w2="$(worker_node 2)"
  check_gate "Deployment edge-proxy exists" exists -n $NS deploy edge-proxy
  check_eq "Image nginx:1.28, $REPLICAS replicas" \
    "$(jp -n $NS deploy edge-proxy "{.spec.replicas} $_t.containers[0].image}")" "$REPLICAS nginx:1.28"
  local me="$_t.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[*].matchExpressions[?(@.key==\"node-pool\")]"
  check_eq "Required node affinity: node-pool In [$POOL]" \
    "$(jp -n $NS deploy edge-proxy "$me.operator} $me.values[*]}")" "In $POOL"
  check_eq "Topology spread: maxSkew 1 over kubernetes.io/hostname, DoNotSchedule" \
    "$(jp -n $NS deploy edge-proxy "$_t.topologySpreadConstraints[0].maxSkew} $_t.topologySpreadConstraints[0].topologyKey} $_t.topologySpreadConstraints[0].whenUnsatisfiable}")" \
    "1 kubernetes.io/hostname DoNotSchedule"
  check_eq "The spread constraint selects the pods (app=edge-proxy)" \
    "$(jp -n $NS deploy edge-proxy "$_t.topologySpreadConstraints[0].labelSelector.matchLabels.app}")" "edge-proxy"
  check_eq "All $REPLICAS replicas are ready" "$(jp -n $NS deploy edge-proxy '{.status.readyReplicas}')" "$REPLICAS"
  local nodes; nodes="$(kc -n $NS get pods -l app=edge-proxy --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ')"
  check_eq "$((REPLICAS / 2)) pods on each worker" "$nodes" "$w1=$((REPLICAS / 2)) $w2=$((REPLICAS / 2)) "
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc label node "$(worker_node 1)" node-pool- >/dev/null 2>&1 || true
  kc label node "$(worker_node 2)" node-pool- >/dev/null 2>&1 || true
}
