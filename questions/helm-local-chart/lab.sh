# shellcheck shell=bash
# Install a local Helm chart. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=monitoring
CHART_SRC="$ITEM_DIR/files/monitoring"

lab_setup() {
  mkdir -p "$WORKDIR/helm-charts"
  rm -rf "$WORKDIR/helm-charts/monitoring"
  cp -r "$CHART_SRC" "$WORKDIR/helm-charts/monitoring"
}

_helm() { helm --kube-context "$CTX" "$@"; }

lab_check() {
  check_gate "Release monitoring-stack is deployed in namespace monitoring" \
    test "$(_helm -n $NS status monitoring-stack -o json 2>/dev/null | jq -r .info.status)" = "deployed"
  local values
  values="$(_helm -n $NS get values monitoring-stack -a -o json 2>/dev/null)"
  check_eq "Value replicaCount is 3" "$(jq -r .replicaCount <<<"$values" 2>/dev/null)" "3"
  check_eq "Value persistence.enabled is true" "$(jq -r .persistence.enabled <<<"$values" 2>/dev/null)" "true"
  check_eq "Value persistence.size is 2Gi" "$(jq -r .persistence.size <<<"$values" 2>/dev/null)" "2Gi"
  check_eq "Deployment monitoring-stack has 3 ready replicas" \
    "$(jp -n $NS deploy monitoring-stack '{.status.readyReplicas}')" "3"
  check_eq "PVC monitoring-stack-data requests 2Gi and is Bound" \
    "$(jp -n $NS pvc monitoring-stack-data '{.spec.resources.requests.storage} {.status.phase}')" "2Gi Bound"
  check "Chart files in $WORKDIR/helm-charts/monitoring are unchanged" \
    diff -r "$CHART_SRC" "$WORKDIR/helm-charts/monitoring"
}

lab_cleanup() {
  helm --kube-context "$CTX" -n "$NS" uninstall monitoring-stack >/dev/null 2>&1 || true
}
