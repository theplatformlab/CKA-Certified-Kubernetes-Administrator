# shellcheck shell=bash
# Exercise 06 — Deployment rolling update and rollback. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=exercise-06

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  check_eq "Deployment webapp has 3 replicas" "$(jp -n $NS deploy webapp '{.spec.replicas}')" "3"
  check_eq "Deployment webapp has 3 ready and updated replicas" \
    "$(jp -n $NS deploy webapp '{.status.readyReplicas}/{.status.updatedReplicas}')" "3/3"
  check_eq "Strategy RollingUpdate with maxSurge=1, maxUnavailable=0" \
    "$(jp -n $NS deploy webapp '{.spec.strategy.type} {.spec.strategy.rollingUpdate.maxSurge} {.spec.strategy.rollingUpdate.maxUnavailable}')" \
    "RollingUpdate 1 0"
  check_eq "Container nginx is back on nginx:1.28 (rolled back)" \
    "$(jp -n $NS deploy webapp '{.spec.template.spec.containers[?(@.name=="nginx")].image}')" "nginx:1.28"

  # rollout history lives in the ReplicaSets owned by the Deployment
  local rs
  rs="$(jp -n $NS rs -l app=webapp '{range .items[*]}{.metadata.annotations.deployment\.kubernetes\.io/revision}|{.spec.template.spec.containers[0].image}|{.metadata.annotations.kubernetes\.io/change-cause}{"\n"}{end}')"
  check_match "A revision with nginx:1.29 exists in the rollout history" "$rs" "\|nginx:1\.29\|"
  check_match "The nginx:1.29 revision has a change-cause" "$rs" "\|nginx:1\.29\|[^|[:space:]]"
  check_match "The nginx:1.28 revision has a change-cause" "$rs" "\|nginx:1\.28\|[^|[:space:]]"
  check_match "Rollback created a new revision (current revision >= 3)" \
    "$(jp -n $NS deploy webapp '{.metadata.annotations.deployment\.kubernetes\.io/revision}')" "^([3-9]|[1-9][0-9]+)$"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
