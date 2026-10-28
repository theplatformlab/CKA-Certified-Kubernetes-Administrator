# shellcheck shell=bash
# Q15 — Namespace resource governance
Q_CLUSTER=practice
NS=batch-jobs

q_setup() { ensure_ns "$NS"; }

_big_pod() {
  kc apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: too-big
  namespace: $NS
spec:
  containers:
  - name: c
    image: busybox:1.37
    resources:
      requests: {cpu: "5", memory: 1Gi}
      limits: {cpu: "5", memory: 1Gi}
EOF
}

q_check() {
  check_gate "ResourceQuota batch-quota exists" exists -n $NS resourcequota batch-quota
  check_eq "batch-quota hard limits" \
    "$(jp -n $NS resourcequota batch-quota '{.spec.hard.requests\.cpu} {.spec.hard.requests\.memory} {.spec.hard.limits\.cpu} {.spec.hard.limits\.memory} {.spec.hard.pods}')" \
    "10 20Gi 10 20Gi 20"
  local lr='{.spec.limits[?(@.type=="Container")]'
  check_eq "batch-limits min 500m/256Mi" "$(jp -n $NS limitrange batch-limits "$lr.min.cpu}/$lr.min.memory}")" "500m/256Mi"
  check_eq "batch-limits max 4/8Gi" "$(jp -n $NS limitrange batch-limits "$lr.max.cpu}/$lr.max.memory}")" "4/8Gi"
  check_eq "batch-limits defaults 500m/256Mi (request and limit)" \
    "$(jp -n $NS limitrange batch-limits "$lr.defaultRequest.cpu}/$lr.defaultRequest.memory} $lr.default.cpu}/$lr.default.memory}")" \
    "500m/256Mi 500m/256Mi"
  check_not "A container requesting 5 CPUs is rejected" _big_pod
}
