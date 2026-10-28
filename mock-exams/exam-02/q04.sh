# shellcheck shell=bash
# Q4 — DaemonSet on all nodes
Q_CLUSTER=practice
NS=monitoring

q_setup() { ensure_ns "$NS"; }

q_check() {
  local nodes; nodes="$(kc get nodes --no-headers 2>/dev/null | wc -l)"
  check_gate "DaemonSet node-agent exists" exists -n $NS ds node-agent
  check_eq "Container agent runs busybox:1.37" \
    "$(jp -n $NS ds node-agent '{.spec.template.spec.containers[?(@.name=="agent")].image}')" "busybox:1.37"
  check_eq "Requests are 10m CPU / 16Mi memory" \
    "$(jp -n $NS ds node-agent '{.spec.template.spec.containers[0].resources.requests.cpu}/{.spec.template.spec.containers[0].resources.requests.memory}')" "10m/16Mi"
  check_eq "Pods are scheduled on all $nodes nodes" "$(jp -n $NS ds node-agent '{.status.desiredNumberScheduled}')" "$nodes"
  check_eq "All $nodes pods are ready" "$(jp -n $NS ds node-agent '{.status.numberReady}')" "$nodes"
}
