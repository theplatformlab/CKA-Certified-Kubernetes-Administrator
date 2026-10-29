# shellcheck shell=bash
# Exercise 20 — Pod Security Standards. Sourced by scripts/lab.sh.
# Setup creates the three namespaces WITHOUT Pod Security labels; labelling is the task.
# The check asks the API server (server-side dry run) whether pods are admitted.
LAB_CLUSTER=practice
NS=exercise-20
NS_BASE=exercise-20-baseline
NS_AUDIT=exercise-20-audit
PSS=pod-security.kubernetes.io

lab_setup() {
  local ns
  for ns in "$NS" "$NS_BASE" "$NS_AUDIT"; do
    kc create namespace "$ns" --dry-run=client -o yaml | kc apply -f -
  done
}

# _admitted <ns> [kubectl run flags...]  — true when a test pod would be admitted
_admitted() {
  local ns="$1"; shift
  kc -n "$ns" run "pss-probe-$RANDOM" --image=nginx:1.28 --dry-run=server "$@" >/dev/null 2>&1
}

_label() { jp ns "$1" "{.metadata.labels.pod-security\.kubernetes\.io/$2}"; }

lab_check() {
  # restricted, enforce
  check_eq "$NS is labelled $PSS/enforce=restricted" "$(_label $NS enforce)" "restricted"
  check_not "$NS rejects a privileged pod" _admitted $NS --privileged
  check_not "$NS rejects a plain nginx pod (not restricted-compliant)" _admitted $NS
  check_eq "Pod secure-pod in $NS is Running" "$(jp -n $NS pod secure-pod '{.status.phase}')" "Running"
  check_eq "secure-pod runs nginx:1.28" "$(jp -n $NS pod secure-pod '{.spec.containers[0].image}')" "nginx:1.28"

  # baseline, enforce
  check_eq "$NS_BASE is labelled $PSS/enforce=baseline" "$(_label $NS_BASE enforce)" "baseline"
  check_not "$NS_BASE rejects a privileged pod" _admitted $NS_BASE --privileged
  check "$NS_BASE admits a plain nginx pod" _admitted $NS_BASE
  check_eq "Pod baseline-pod in $NS_BASE is Running" "$(jp -n $NS_BASE pod baseline-pod '{.status.phase}')" "Running"
  check_not "No pod named priv-pod exists in $NS_BASE" exists -n $NS_BASE pod priv-pod

  # restricted, audit + warn only
  check_eq "$NS_AUDIT is labelled $PSS/audit=restricted" "$(_label $NS_AUDIT audit)" "restricted"
  check_eq "$NS_AUDIT is labelled $PSS/warn=restricted" "$(_label $NS_AUDIT warn)" "restricted"
  check_eq "$NS_AUDIT has no $PSS/enforce label" "$(_label $NS_AUDIT enforce)" ""
  check_eq "Privileged pod audit-pod in $NS_AUDIT is Running" \
    "$(jp -n $NS_AUDIT pod audit-pod '{.status.phase} privileged={.spec.containers[0].securityContext.privileged}')" \
    "Running privileged=true"
}

lab_cleanup() {
  kc delete namespace "$NS" "$NS_BASE" "$NS_AUDIT" --ignore-not-found --wait=false
}
