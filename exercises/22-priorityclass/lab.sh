# shellcheck shell=bash
# Exercise 22 — PriorityClass. Sourced by scripts/lab.sh.
# PriorityClasses are cluster-scoped: cleanup removes them explicitly.
LAB_CLUSTER=practice
NS=exercise-22

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  check_eq "PriorityClass high-priority: value 1000, PreemptLowerPriority" \
    "$(jp priorityclass high-priority '{.value} {.preemptionPolicy}')" "1000 PreemptLowerPriority"
  check_eq "PriorityClass low-priority: value 10, Never" \
    "$(jp priorityclass low-priority '{.value} {.preemptionPolicy}')" "10 Never"
  local hd ld
  hd="$(jp priorityclass high-priority '{.globalDefault}')"
  ld="$(jp priorityclass low-priority '{.globalDefault}')"
  check_eq "Neither class is the global default" "${hd:-false}/${ld:-false}" "false/false"

  check_eq "Pod critical-app runs nginx:1.28" \
    "$(jp -n $NS pod critical-app '{.spec.containers[0].image}')" "nginx:1.28"
  check_eq "Pod critical-app uses high-priority (priority 1000)" \
    "$(jp -n $NS pod critical-app '{.spec.priorityClassName} {.spec.priority}')" "high-priority 1000"
  check_eq "Pod critical-app is Running" "$(jp -n $NS pod critical-app '{.status.phase}')" "Running"

  check_eq "Pod background-job runs busybox:1.37" \
    "$(jp -n $NS pod background-job '{.spec.containers[0].image}')" "busybox:1.37"
  check_eq "Pod background-job runs 'sleep 3600'" \
    "$(jp -n $NS pod background-job '{.spec.containers[0].command[*]} {.spec.containers[0].args[*]}' | xargs)" "sleep 3600"
  check_eq "Pod background-job uses low-priority (priority 10)" \
    "$(jp -n $NS pod background-job '{.spec.priorityClassName} {.spec.priority}')" "low-priority 10"
  check_eq "Pod background-job is Running" "$(jp -n $NS pod background-job '{.status.phase}')" "Running"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc delete priorityclass high-priority low-priority --ignore-not-found
  # Task 6 (optional) drains a node — make every node schedulable again.
  local n
  for n in $(kc get nodes -o name); do kc uncordon "$n" >/dev/null || true; done
}
