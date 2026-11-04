# shellcheck shell=bash
# ResourceQuota and LimitRange. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=test

lab_setup() { ensure_ns "$NS"; }

# _pod_dry_run [cpu memory] -> server-side dry run of a pod; prints the effective requests
_pod_dry_run() {
  local resources=""
  if [[ -n "${1:-}" ]]; then
    resources="
    resources:
      requests: {cpu: \"$1\", memory: \"$2\"}
      limits: {cpu: \"$1\", memory: \"$2\"}"
  fi
  kc apply --dry-run=server -o jsonpath='{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.requests.memory}' -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: quota-check
  namespace: $NS
spec:
  containers:
  - name: c
    image: busybox:1.37$resources
EOF
}

lab_check() {
  check_gate "ResourceQuota compute-quota exists" exists -n $NS resourcequota compute-quota
  check_eq "ResourceQuota compute-quota limits" \
    "$(jp -n $NS resourcequota compute-quota '{.spec.hard.requests\.cpu} {.spec.hard.requests\.memory} {.spec.hard.limits\.cpu} {.spec.hard.limits\.memory}')" \
    "4 8Gi 4 8Gi"
  local lr='{.spec.limits[?(@.type=="Container")]'
  check_eq "LimitRange container-limits: default request 100m/128Mi" \
    "$(jp -n $NS limitrange container-limits "$lr.defaultRequest.cpu}/$lr.defaultRequest.memory}")" "100m/128Mi"
  check_eq "LimitRange container-limits: default limit 200m/256Mi" \
    "$(jp -n $NS limitrange container-limits "$lr.default.cpu}/$lr.default.memory}")" "200m/256Mi"
  check_eq "LimitRange container-limits: min 100m/128Mi" \
    "$(jp -n $NS limitrange container-limits "$lr.min.cpu}/$lr.min.memory}")" "100m/128Mi"
  check_eq "LimitRange container-limits: max 1/1Gi" \
    "$(jp -n $NS limitrange container-limits "$lr.max.cpu}/$lr.max.memory}")" "1/1Gi"
  check_not "A pod requesting 2 CPUs / 2Gi is rejected" _pod_dry_run 2 2Gi
  check_eq "A pod without resources gets the default requests" "$(_pod_dry_run 2>/dev/null)" "100m/128Mi"
}
