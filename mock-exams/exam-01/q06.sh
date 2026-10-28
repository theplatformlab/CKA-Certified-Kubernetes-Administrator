# shellcheck shell=bash
# Q6 — Install a local Helm chart
Q_CLUSTER=practice
NS=monitoring
CHART_SRC="$REPO_ROOT/mock-exams/exam-01/files/monitoring"

q_setup() {
  mkdir -p "$CKA_EXAM_HOME/helm-charts"
  rm -rf "$CKA_EXAM_HOME/helm-charts/monitoring"
  cp -r "$CHART_SRC" "$CKA_EXAM_HOME/helm-charts/monitoring"
}

_helm() { helm --kube-context "$CTX" "$@"; }

q_check() {
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
  check "Chart files in ~/cka-exam/helm-charts/monitoring are unchanged" \
    diff -r "$CHART_SRC" "$CKA_EXAM_HOME/helm-charts/monitoring"
}
