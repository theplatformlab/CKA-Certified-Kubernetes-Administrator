# shellcheck shell=bash
# Q2 — Roll back a broken rollout
Q_CLUSTER=practice
NS=payments

q_setup() {
  ensure_ns "$NS"
  mkdir -p "$CKA_EXAM_HOME/q02"
  kc -n $NS create deployment payment-service --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml | kc apply -f -
  kc -n $NS annotate deploy payment-service kubernetes.io/change-cause="initial release nginx:1.27" --overwrite
  kc -n $NS rollout status deploy payment-service --timeout=300s
  kc -n $NS set image deploy payment-service nginx=nginx:1.28
  kc -n $NS annotate deploy payment-service kubernetes.io/change-cause="upgrade to nginx:1.28" --overwrite
  kc -n $NS rollout status deploy payment-service --timeout=300s
  kc -n $NS set image deploy payment-service nginx=nginx:1.28.99
  kc -n $NS annotate deploy payment-service kubernetes.io/change-cause="upgrade to nginx:1.28.99" --overwrite
}

q_check() {
  check_gate "~/cka-exam/q02/broken-revision.txt exists" test -s "$CKA_EXAM_HOME/q02/broken-revision.txt"
  check_eq "broken-revision.txt contains revision 3" "$(tr -d '[:space:]' <"$CKA_EXAM_HOME/q02/broken-revision.txt" 2>/dev/null)" "3"
  check_eq "Deployment payment-service runs nginx:1.28 again" \
    "$(jp -n $NS deploy payment-service '{.spec.template.spec.containers[0].image}')" "nginx:1.28"
  check_eq "3/3 replicas updated and ready" \
    "$(jp -n $NS deploy payment-service '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "3/3/3"
  check_not "No pods with the broken image are left" \
    bash -c "kubectl --context '$CTX' -n $NS get pods -o jsonpath='{.items[*].spec.containers[*].image}' | grep -q 1.28.99"
}
