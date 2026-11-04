# shellcheck shell=bash
# Pod Security Standards. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=restricted

lab_setup() {
  ensure_ns "$NS"
  kc -n "$NS" create deployment web --image=nginxinc/nginx-unprivileged:1.28-alpine --dry-run=client -o yaml | kc apply -f -
}

_privileged_dry_run() {
  kc apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged-check
  namespace: $NS
spec:
  containers:
  - name: c
    image: busybox:1.37
    securityContext:
      privileged: true
EOF
}

lab_check() {
  local l='{.metadata.labels.pod-security\.kubernetes\.io/'
  check_gate "Namespace label enforce=restricted" test "$(jp ns $NS "${l}enforce}")" = "restricted"
  check_eq "Namespace label warn=restricted" "$(jp ns $NS "${l}warn}")" "restricted"
  check_eq "Namespace label audit=baseline" "$(jp ns $NS "${l}audit}")" "baseline"
  check_eq "Deployment web still uses nginxinc/nginx-unprivileged:1.28-alpine" \
    "$(jp -n $NS deploy web '{.spec.template.spec.containers[0].image}')" "nginxinc/nginx-unprivileged:1.28-alpine"
  check "Pod template of web passes the restricted profile (server dry-run)" \
    bash -c "kubectl --context '$CTX' -n $NS get deploy web -o json \
      | jq '{apiVersion:\"v1\",kind:\"Pod\",metadata:{name:\"psa-check\",namespace:\"$NS\"},spec:.spec.template.spec}' \
      | kubectl --context '$CTX' apply --dry-run=server -f -"
  check_eq "Pod template sets allowPrivilegeEscalation=false and drops ALL capabilities" \
    "$(jp -n $NS deploy web '{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation} {.spec.template.spec.containers[0].securityContext.capabilities.drop[*]}')" \
    "false ALL"
  check_eq "All replicas of web are up to date and ready" \
    "$(jp -n $NS deploy web '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "1/1/1"
  check_not "A privileged pod is rejected" _privileged_dry_run
}
