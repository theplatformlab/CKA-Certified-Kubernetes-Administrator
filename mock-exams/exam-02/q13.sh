# shellcheck shell=bash
# Q13 — Pod Security Admission
Q_CLUSTER=practice
NS=secure-apps

q_setup() { mkdir -p "$CKA_EXAM_HOME/q13"; }

q_check() {
  local l='{.metadata.labels.pod-security\.kubernetes\.io/'
  check_gate "Namespace secure-apps enforces restricted" test "$(jp ns $NS "${l}enforce}")" = "restricted"
  check_eq "Namespace secure-apps warns on restricted" "$(jp ns $NS "${l}warn}")" "restricted"
  check_eq "Pod restricted-pod runs nginxinc/nginx-unprivileged:1.28-alpine" \
    "$(jp -n $NS pod restricted-pod '{.spec.containers[0].image} {.status.phase}')" "nginxinc/nginx-unprivileged:1.28-alpine Running"
  check_not "Pod blocked-pod does not exist" exists -n $NS pod blocked-pod
  check_contains "error.txt contains the PodSecurity rejection" \
    "$(cat "$CKA_EXAM_HOME/q13/error.txt" 2>/dev/null)" 'violates PodSecurity "restricted'
}
