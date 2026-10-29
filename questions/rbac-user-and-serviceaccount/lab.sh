# shellcheck shell=bash
# RBAC for a user and a ServiceAccount. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=staging

lab_setup() {
  ensure_ns "$NS"
  kc -n "$NS" create deployment web --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
}

_can() { kc auth can-i "$@"; }

lab_check() {
  local sa="system:serviceaccount:$NS:ci-bot"
  check_gate "Role dev-reader exists" exists -n $NS role dev-reader
  check_eq "RoleBinding dev-reader-binding references Role dev-reader" \
    "$(jp -n $NS rolebinding dev-reader-binding '{.roleRef.kind}/{.roleRef.name}')" "Role/dev-reader"
  check "dev-user can list pods in staging" _can list pods -n $NS --as dev-user
  check "dev-user can watch deployments in staging" _can watch deployments.apps -n $NS --as dev-user
  check "dev-user can get deployments in staging" _can get deployments.apps -n $NS --as dev-user
  check_not "dev-user cannot delete pods in staging" _can delete pods -n $NS --as dev-user
  check_not "dev-user cannot read secrets in staging" _can get secrets -n $NS --as dev-user
  check_not "dev-user cannot list pods in default" _can list pods -n default --as dev-user
  check "ServiceAccount ci-bot can list deployments in staging" _can list deployments.apps -n $NS --as "$sa"
  check_not "ServiceAccount ci-bot cannot create deployments in staging" _can create deployments.apps -n $NS --as "$sa"
}
