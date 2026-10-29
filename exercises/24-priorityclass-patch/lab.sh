# shellcheck shell=bash
# Exercise 24 — PriorityClass and kubectl patch. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-24}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

# _priorities <label-selector>  — spec.priority of every Running pod that is not terminating
_priorities() {
  kc -n "$NS" get pods -l "$1" --field-selector status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.spec.priority}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' '$1 == "" {print $2}' | sort -u | paste -sd' '
}

lab_check() {
  check_eq "PriorityClass high-priority has value 999999" "$(jp priorityclass high-priority '{.value}')" "999999"
  check_eq "PriorityClass high-priority has description 'Critical workload'" \
    "$(jp priorityclass high-priority '{.description}')" "Critical workload"
  check_eq "PriorityClass high-priority is not the global default" \
    "$(x="$(jp priorityclass high-priority '{.globalDefault}')"; echo "${x:-false}")" "false"
  check_eq "PriorityClass low-priority has value 1000" "$(jp priorityclass low-priority '{.value}')" "1000"

  check_eq "Deployment critical-app runs 1 replica of busybox:1.36" \
    "$(jp -n $NS deploy critical-app '{.spec.replicas} {.spec.template.spec.containers[0].image}')" "1 busybox:1.36"
  check_eq "critical-app pod template has priorityClassName high-priority" \
    "$(jp -n $NS deploy critical-app '{.spec.template.spec.priorityClassName}')" "high-priority"
  check_match "critical-app was changed after creation (rollout revision >= 2, i.e. patched)" \
    "$(jp -n $NS deploy critical-app '{.metadata.annotations.deployment\.kubernetes\.io/revision}')" "^([2-9]|[1-9][0-9]+)$"
  check_eq "critical-app has 1 ready replica (container keeps running)" \
    "$(jp -n $NS deploy critical-app '{.status.readyReplicas}')" "1"
  check_eq "The running critical-app pod has priority 999999" "$(_priorities app=critical-app)" "999999"

  check_eq "Deployment background-app uses priorityClassName low-priority" \
    "$(jp -n $NS deploy background-app '{.spec.template.spec.priorityClassName}')" "low-priority"
  check_eq "background-app has 1 ready replica" "$(jp -n $NS deploy background-app '{.status.readyReplicas}')" "1"
  check_eq "The running background-app pod has priority 1000" "$(_priorities app=background-app)" "1000"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc delete priorityclass high-priority low-priority --ignore-not-found
}
