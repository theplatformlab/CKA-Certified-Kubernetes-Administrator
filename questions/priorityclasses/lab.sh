# shellcheck shell=bash
# PriorityClasses. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=priority

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  check_gate "PriorityClass critical-workload exists" exists priorityclass critical-workload
  check_eq "critical-workload: value 1000000, description critical" \
    "$(jp priorityclass critical-workload '{.value} {.description}')" "1000000 critical"
  check_eq "standard-workload: value 1000, preemptionPolicy Never" \
    "$(jp priorityclass standard-workload '{.value} {.preemptionPolicy}')" "1000 Never"
  check_not "Neither PriorityClass is the global default" \
    bash -c "kubectl --context '$CTX' get priorityclass critical-workload standard-workload -o jsonpath='{.items[*].globalDefault}' | grep -q true"
  check_eq "Deployment critical-app uses critical-workload and has 2 ready replicas" \
    "$(jp -n $NS deploy critical-app '{.spec.template.spec.priorityClassName} {.status.readyReplicas}')" "critical-workload 2"
  check_eq "critical-app pods run with priority 1000000" \
    "$(kc -n $NS get pods -l app=critical-app -o jsonpath='{.items[*].spec.priority}' 2>/dev/null | tr ' ' '\n' | sort -u | tr -d '\n')" "1000000"
  check_eq "Pod batch-job uses standard-workload (priority 1000) and is Running" \
    "$(jp -n $NS pod batch-job '{.spec.priorityClassName} {.spec.priority} {.status.phase}')" "standard-workload 1000 Running"
}

lab_cleanup() {
  kc delete priorityclass critical-workload standard-workload --ignore-not-found >/dev/null 2>&1 || true
}
