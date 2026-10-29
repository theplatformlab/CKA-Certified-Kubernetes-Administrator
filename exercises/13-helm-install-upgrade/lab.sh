# shellcheck shell=bash
# Exercise 13 — Helm install, upgrade, rollback. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-13}"
REL=web

_helm() { helm --kube-context "$CTX" "$@"; }

lab_setup() {
  local tool
  for tool in helm jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_error "$tool is not installed (needed for this exercise and its check)"
      return 1
    fi
  done
  # Start from scratch: no release, no namespace (Helm creates it with --create-namespace).
  if _helm status "$REL" -n "$NS" >/dev/null 2>&1; then
    _helm uninstall "$REL" -n "$NS" --wait
  fi
  kc delete namespace "$NS" --ignore-not-found --wait=true
  echo "  Namespace $NS does not exist yet — create it with helm install --create-namespace."
}

lab_check() {
  if ! command -v helm >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    check "helm and jq are installed" false
    return
  fi
  check_eq "Release web is deployed in $NS" \
    "$(_helm status "$REL" -n "$NS" -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null)" "deployed"

  local hist
  hist="$(_helm history "$REL" -n "$NS" -o json 2>/dev/null)"
  check_eq "Release history has 3 revisions (install, upgrade, rollback)" \
    "$(jq -r 'length' <<<"$hist" 2>/dev/null)" "3"
  check_eq "Revision 1 installed chart podinfo-6.16.0" \
    "$(jq -r '.[] | select(.revision==1) | .chart' <<<"$hist" 2>/dev/null)" "podinfo-6.16.0"
  check_eq "Revision 2 upgraded to chart podinfo-6.17.0" \
    "$(jq -r '.[] | select(.revision==2) | .chart' <<<"$hist" 2>/dev/null)" "podinfo-6.17.0"
  check_eq "Revision 2 set replicaCount=3" \
    "$(_helm get values "$REL" -n "$NS" --revision 2 -o json 2>/dev/null | jq -r '.replicaCount' 2>/dev/null)" "3"
  check_eq "Revision 3 is a rollback to revision 1" \
    "$(jq -r '.[] | select(.revision==3) | .description' <<<"$hist" 2>/dev/null)" "Rollback to 1"

  check_eq "Current release runs chart podinfo-6.16.0" \
    "$(jq -r '.[-1].chart' <<<"$hist" 2>/dev/null)" "podinfo-6.16.0"
  check_eq "Current release values have replicaCount=2" \
    "$(_helm get values "$REL" -n "$NS" -o json 2>/dev/null | jq -r '.replicaCount' 2>/dev/null)" "2"
  check_eq "Deployment web-podinfo has 2 replicas" "$(jp -n $NS deploy web-podinfo '{.spec.replicas}')" "2"
  check_eq "Deployment web-podinfo has 2 ready pods" "$(jp -n $NS deploy web-podinfo '{.status.readyReplicas}')" "2"
  check_eq "Deployment web-podinfo runs podinfo 6.16.0" \
    "$(jp -n $NS deploy web-podinfo '{.spec.template.spec.containers[0].image}')" "ghcr.io/stefanprodan/podinfo:6.16.0"
}

lab_cleanup() {
  if command -v helm >/dev/null 2>&1 && _helm status "$REL" -n "$NS" >/dev/null 2>&1; then
    _helm uninstall "$REL" -n "$NS" --wait || true
  fi
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
