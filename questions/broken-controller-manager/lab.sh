# shellcheck shell=bash
# Deployment creates no pods (kube-controller-manager crashes on a mistyped flag).
# Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
NS=ledger
MANIFEST=/etc/kubernetes/manifests/kube-controller-manager.yaml
GOOD_FLAG=--cluster-signing-key-file=
BAD_FLAG=--cluster-signing-keyfile=

lab_setup() {
  local cp; cp="$(control_plane_node)"
  # Stop the controller manager first so it can't create the ReplicaSet, then put back a broken manifest.
  node_exec "$cp" "
    set -e
    mv $MANIFEST /root/kube-controller-manager.yaml.orig
    for i in \$(seq 1 60); do crictl ps -q --name kube-controller-manager | grep -q . || break; sleep 1; done
    sed 's|- $GOOD_FLAG|- $BAD_FLAG|' /root/kube-controller-manager.yaml.orig > $MANIFEST
    rm /root/kube-controller-manager.yaml.orig
  "
  ensure_ns "$NS"
  kc -n "$NS" create deployment invoice-api --image=nginx:1.28 --replicas=3 --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  local cp; cp="$(control_plane_node)"
  check_gate "kube-controller-manager pod is Ready" \
    test "$(jp -n kube-system pod "kube-controller-manager-$cp" '{.status.conditions[?(@.type=="Ready")].status}')" = "True"
  check_eq "kube-controller-manager has --cluster-signing-key-file=/etc/kubernetes/pki/ca.key" \
    "$(node_exec "$cp" "grep -o -- '--cluster-signing-key[^ \"]*' $MANIFEST" 2>/dev/null)" \
    "--cluster-signing-key-file=/etc/kubernetes/pki/ca.key"
  check_eq "kube-controller-manager container is running" \
    "$(node_exec "$cp" "crictl ps --name kube-controller-manager --state running -q | wc -l" 2>/dev/null)" "1"
  check_eq "Deployment invoice-api is unchanged (3 replicas, nginx:1.28)" \
    "$(jp -n $NS deploy invoice-api '{.spec.replicas} {.spec.template.spec.containers[0].image}')" "3 nginx:1.28"
  check_eq "Deployment invoice-api has 3 ready replicas" "$(jp -n $NS deploy invoice-api '{.status.readyReplicas}')" "3"
}

lab_cleanup() {
  node_exec "$(control_plane_node)" "sed -i 's|- $BAD_FLAG|- $GOOD_FLAG|' $MANIFEST"
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
