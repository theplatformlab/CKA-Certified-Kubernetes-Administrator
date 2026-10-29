# shellcheck shell=bash
# Kubelet and container runtime. Sourced by scripts/lab.sh.
LAB_CLUSTER=ops

lab_setup() {
  local node; node="$(worker_node 1)"
  backup_node_file "$node" /var/lib/kubelet/config.yaml
  node_exec "$node" "
    sed -i 's|^containerRuntimeEndpoint:.*|containerRuntimeEndpoint: unix:///run/cri-dockerd.sock|' /var/lib/kubelet/config.yaml
    systemctl disable kubelet >/dev/null 2>&1
    systemctl restart kubelet
  "
}

lab_check() {
  local node; node="$(worker_node 1)"
  check_gate "Node $node is Ready" \
    test "$(kc --request-timeout=10s get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True"
  check_eq "kubelet config uses the containerd socket" \
    "$(node_exec "$node" "sed -n 's/^containerRuntimeEndpoint: *//p' /var/lib/kubelet/config.yaml" 2>/dev/null)" \
    "unix:///run/containerd/containerd.sock"
  check_eq "kubelet service is active" "$(node_exec "$node" "systemctl is-active kubelet" 2>/dev/null)" "active"
  check_eq "kubelet service is enabled at boot" "$(node_exec "$node" "systemctl is-enabled kubelet" 2>/dev/null)" "enabled"
  check_match "Node reports containerd as runtime" \
    "$(jp node "$node" '{.status.nodeInfo.containerRuntimeVersion}')" '^containerd://'
}

lab_cleanup() {
  local node; node="$(worker_node 1)"
  restore_node_file "$node" /var/lib/kubelet/config.yaml
  node_exec "$node" "systemctl enable kubelet >/dev/null 2>&1; systemctl restart kubelet"
}
