# shellcheck shell=bash
# Q5 — API server is down (broken --client-ca-file)
Q_CLUSTER=ops
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml

q_setup() {
  node_exec "$(control_plane_node)" \
    "sed -i 's|- --client-ca-file=/etc/kubernetes/pki/ca.crt|- --client-ca-file=/etc/kubernetes/pki/client-ca.crt|' $MANIFEST"
}

q_check() {
  check_gate "API server answers /readyz" kc --request-timeout=10s get --raw /readyz
  check_eq "--client-ca-file points to /etc/kubernetes/pki/ca.crt" \
    "$(node_exec "$(control_plane_node)" "grep -o -- '--client-ca-file=[^ \"]*' $MANIFEST" 2>/dev/null)" \
    "--client-ca-file=/etc/kubernetes/pki/ca.crt"
  check_eq "kube-apiserver pod is Ready" \
    "$(kc --request-timeout=10s -n kube-system get pod "kube-apiserver-$(control_plane_node)" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" "True"
  check "Nodes can be listed" kc --request-timeout=10s get nodes
}
