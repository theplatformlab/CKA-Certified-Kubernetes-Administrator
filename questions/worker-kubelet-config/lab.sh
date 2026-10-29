# shellcheck shell=bash
# Worker node NotReady (kubelet systemd drop-in points to a wrong kubeconfig path).
# Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
DROPIN=/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
GOOD=--kubeconfig=/etc/kubernetes/kubelet.conf
BAD=--kubeconfig=/etc/kubernetes/kubelet.config

lab_setup() {
  local node; node="$(worker_node 1)"
  node_exec "$node" "
    set -e
    sed -i 's|$GOOD\\([ \"]\\)|$BAD\\1|' $DROPIN
    grep -q -- '$BAD' $DROPIN
    systemctl daemon-reload
    systemctl restart kubelet
  "
  echo "  Waiting for $node to become NotReady ..."
  kc wait --for=condition=Ready=Unknown "node/$node" --timeout=120s >/dev/null 2>&1 || true
}

_kubelet_args() { node_exec "$(worker_node 1)" "tr '\\0' ' ' < /proc/\$(pgrep -xo kubelet)/cmdline" 2>/dev/null; }

lab_check() {
  local node; node="$(worker_node 1)"
  check_gate "Node $node is Ready" \
    test "$(kc --request-timeout=10s get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True"
  check_eq "kubelet service is active" "$(node_exec "$node" "systemctl is-active kubelet" 2>/dev/null)" "active"
  check_contains "Running kubelet uses $GOOD" "$(_kubelet_args)" "$GOOD "
  check_eq "kubeadm drop-in sets $GOOD" \
    "$(node_exec "$node" "grep -o -- '--kubeconfig=[^ \"]*' $DROPIN" 2>/dev/null)" "$GOOD"
  check_not "No /etc/kubernetes/kubelet.config was created as a workaround" \
    node_exec "$node" "test -e /etc/kubernetes/kubelet.config"
}

lab_cleanup() {
  node_exec "$(worker_node 1)" "
    if grep -q -- '$BAD' $DROPIN; then
      sed -i 's|$BAD\\([ \"]\\)|$GOOD\\1|' $DROPIN
      systemctl daemon-reload
      systemctl restart kubelet
    fi
  "
}
