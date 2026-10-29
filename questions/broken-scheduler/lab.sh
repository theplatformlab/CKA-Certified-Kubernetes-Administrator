# shellcheck shell=bash
# Pods stuck in Pending (broken kube-scheduler). Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
MANIFEST=/etc/kubernetes/manifests/kube-scheduler.yaml

lab_setup() {
  local cp; cp="$(control_plane_node)"
  backup_node_file "$cp" "$MANIFEST"
  # Stop the scheduler first so it can't place the new pods, then put back a broken manifest.
  node_exec "$cp" "
    set -e
    mv $MANIFEST /root/kube-scheduler.yaml.orig
    for i in \$(seq 1 60); do crictl ps -q --name kube-scheduler | grep -q . || break; sleep 1; done
    sed 's|- --kubeconfig=/etc/kubernetes/scheduler.conf|- --kubeconfig=/etc/kubernetes/scheduler.config|' \
      /root/kube-scheduler.yaml.orig > $MANIFEST
    rm /root/kube-scheduler.yaml.orig
  "
  kc -n default create deployment rescue --image=nginx:1.28 --replicas=2 --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  local cp; cp="$(control_plane_node)"
  check_gate "kube-scheduler pod is Ready" \
    test "$(jp -n kube-system pod "kube-scheduler-$cp" '{.status.conditions[?(@.type=="Ready")].status}')" = "True"
  check_eq "kube-scheduler uses --kubeconfig=/etc/kubernetes/scheduler.conf" \
    "$(node_exec "$cp" "grep -o -- '--kubeconfig=[^ \"]*' $MANIFEST" 2>/dev/null)" "--kubeconfig=/etc/kubernetes/scheduler.conf"
  check_eq "Deployment rescue is unchanged (2 replicas, nginx:1.28)" \
    "$(jp -n default deploy rescue '{.spec.replicas} {.spec.template.spec.containers[0].image}')" "2 nginx:1.28"
  check_eq "Deployment rescue has 2 ready replicas" "$(jp -n default deploy rescue '{.status.readyReplicas}')" "2"
}

lab_cleanup() {
  restore_node_file "$(control_plane_node)" "$MANIFEST"
  kc -n default delete deployment rescue --ignore-not-found >/dev/null 2>&1 || true
}
