# shellcheck shell=bash
# Helm repository, upgrade and rollback. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=helm-apps
REL=web

lab_params() {
  echo "REPLICAS_OLD=$(pick 2 3)"
  echo "REPLICAS_NEW=$(pick 4 5)"
}

_helm() { helm --kube-context "$CTX" "$@"; }

lab_setup() {
  local tool
  for tool in helm jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_error "$tool is not installed (needed for this item and its check)"
      return 1
    fi
  done
  # Start from scratch: no release, no namespace (helm install --create-namespace creates it).
  if _helm status "$REL" -n "$NS" >/dev/null 2>&1; then
    _helm uninstall "$REL" -n "$NS" --wait
  fi
  kc delete namespace "$NS" --ignore-not-found --wait=true >/dev/null
}

lab_check() {
  check_gate "Release web exists in $NS" _helm status "$REL" -n "$NS"
  local hist
  hist="$(_helm history "$REL" -n "$NS" -o json 2>/dev/null)"
  check_eq "Release web is deployed" \
    "$(_helm status "$REL" -n "$NS" -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null)" "deployed"
  check_eq "Revision 1 installed chart podinfo-6.16.0" \
    "$(jq -r '.[] | select(.revision==1) | .chart' <<<"$hist" 2>/dev/null)" "podinfo-6.16.0"
  check_eq "Revision 2 upgraded to chart podinfo-6.17.0 with replicaCount=$REPLICAS_NEW" \
    "$(jq -r '.[] | select(.revision==2) | .chart' <<<"$hist" 2>/dev/null) $(_helm get values "$REL" -n "$NS" --revision 2 -o json 2>/dev/null | jq -r '.replicaCount' 2>/dev/null)" \
    "podinfo-6.17.0 $REPLICAS_NEW"
  check_eq "The latest revision is a rollback to revision 1" \
    "$(jq -r '.[-1].description' <<<"$hist" 2>/dev/null)" "Rollback to 1"
  check_eq "Current release runs chart podinfo-6.16.0 with replicaCount=$REPLICAS_OLD" \
    "$(jq -r '.[-1].chart' <<<"$hist" 2>/dev/null) $(_helm get values "$REL" -n "$NS" -o json 2>/dev/null | jq -r '.replicaCount' 2>/dev/null)" \
    "podinfo-6.16.0 $REPLICAS_OLD"
  check_eq "Deployment web-podinfo runs podinfo 6.16.0" \
    "$(jp -n $NS deploy web-podinfo '{.spec.template.spec.containers[0].image}')" "ghcr.io/stefanprodan/podinfo:6.16.0"
  check_eq "Deployment web-podinfo has $REPLICAS_OLD/$REPLICAS_OLD ready replicas" \
    "$(jp -n $NS deploy web-podinfo '{.spec.replicas}/{.status.readyReplicas}')" "$REPLICAS_OLD/$REPLICAS_OLD"
}

lab_cleanup() {
  if command -v helm >/dev/null 2>&1 && _helm status "$REL" -n "$NS" >/dev/null 2>&1; then
    _helm uninstall "$REL" -n "$NS" --wait >/dev/null || true
  fi
}
