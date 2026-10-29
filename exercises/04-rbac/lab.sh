# shellcheck shell=bash
# Exercise 04 — RBAC. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-04}"
SA="system:serviceaccount:$NS:dev-sa"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

# _can <verb> <resource> [kubectl args...]  — true when dev-sa is allowed.
_can() { kc auth can-i "$1" "$2" --as="$SA" "${@:3}"; }

lab_check() {
  check "ServiceAccount dev-sa exists in $NS" exists -n $NS sa dev-sa
  check "Role pod-manager exists in $NS" exists -n $NS role pod-manager
  check_eq "RoleBinding dev-pod-access references Role pod-manager" \
    "$(jp -n $NS rolebinding dev-pod-access '{.roleRef.kind}/{.roleRef.name}')" "Role/pod-manager"
  check_eq "RoleBinding dev-pod-access binds ServiceAccount $NS/dev-sa" \
    "$(jp -n $NS rolebinding dev-pod-access '{.subjects[?(@.kind=="ServiceAccount")].namespace}/{.subjects[?(@.kind=="ServiceAccount")].name}')" \
    "$NS/dev-sa"

  local v
  for v in get list watch create delete; do
    check "dev-sa can $v pods in $NS" _can "$v" pods -n $NS
  done
  check_not "dev-sa cannot update pods in $NS (not granted)" _can update pods -n $NS
  check "dev-sa can get services in $NS" _can get services -n $NS
  check "dev-sa can list services in $NS" _can list services -n $NS
  check_not "dev-sa cannot delete services in $NS" _can delete services -n $NS
  check_not "dev-sa cannot delete deployments in $NS" _can delete deployments.apps -n $NS
  check_not "dev-sa cannot list pods in default" _can list pods -n default

  check_eq "ClusterRoleBinding dev-node-access references ClusterRole node-viewer" \
    "$(jp clusterrolebinding dev-node-access '{.roleRef.kind}/{.roleRef.name}')" "ClusterRole/node-viewer"
  check_eq "ClusterRoleBinding dev-node-access binds ServiceAccount $NS/dev-sa" \
    "$(jp clusterrolebinding dev-node-access '{.subjects[?(@.kind=="ServiceAccount")].namespace}/{.subjects[?(@.kind=="ServiceAccount")].name}')" \
    "$NS/dev-sa"
  check "dev-sa can get nodes" _can get nodes
  check "dev-sa can list nodes" _can list nodes
  check_not "dev-sa cannot delete nodes" _can delete nodes
}

lab_cleanup() {
  kc delete clusterrolebinding dev-node-access --ignore-not-found
  kc delete clusterrole node-viewer --ignore-not-found
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
