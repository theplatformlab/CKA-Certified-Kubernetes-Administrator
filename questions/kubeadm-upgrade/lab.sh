# shellcheck shell=bash
# Upgrade the cluster with kubeadm. Sourced by scripts/lab.sh.
# The ops cluster starts on v1.35.x and every node has the pkgs.k8s.io apt repo
# for v1.36 configured (see prepare_ops_nodes in scripts/init-cluster.sh).
# The upgrade is one-way: to practise again, recreate the cluster.
LAB_CLUSTER=ops

_kc() { kc --request-timeout=10s "$@"; }

# Latest kubeadm patch release in the node's apt repo, e.g. 1.36.6
_target_version() {
  node_exec "$(control_plane_node)" "apt-cache madison kubeadm 2>/dev/null | awk '{print \$3}' | sed 's/-.*//' | sort -V | tail -1"
}

_nodes() { _kc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null; }

lab_setup() {
  local node version target
  for node in $(_nodes); do
    if ! node_exec "$node" "test -f /etc/apt/sources.list.d/kubernetes.list"; then
      log_error "$node has no Kubernetes apt repository. Recreate the cluster:"
      echo "  ./scripts/init-cluster.sh --profile ops --recreate" >&2
      return 1
    fi
  done
  version="$(jp node "$(control_plane_node)" '{.status.nodeInfo.kubeletVersion}')"
  if [[ "$version" != v1.35.* ]]; then
    log_error "The cluster is on $version, not v1.35.x: it was already upgraded. Recreate it:"
    echo "  ./scripts/init-cluster.sh --profile ops --recreate" >&2
    return 1
  fi
  node_exec "$(control_plane_node)" "apt-get update -qq" >/dev/null 2>&1 || true
  target="$(_target_version)"
  echo "  Cluster is on $version. Upgrade target (latest v1.36 patch in the repo): v${target:-?}"
}

lab_check() {
  local target cp node c
  target="$(_target_version)"
  cp="$(control_plane_node)"
  check_gate "kube-apiserver static pod runs v$target" \
    test "$(jp --request-timeout=10s -n kube-system pod "kube-apiserver-$cp" '{.spec.containers[0].image}' | sed 's/.*://')" == "v$target"
  check_match "Upgrade target found in the apt repo (v1.36.x)" "v$target" '^v1\.36\.[0-9]+$'

  for node in $(_nodes); do
    check_eq "Node $node kubelet is v$target" \
      "$(jp --request-timeout=10s node "$node" '{.status.nodeInfo.kubeletVersion}')" "v$target"
    check_eq "Node $node kubeadm is v$target" "$(node_exec "$node" "kubeadm version -o short" 2>/dev/null)" "v$target"
    check_eq "Node $node kubectl is v$target" \
      "$(node_exec "$node" "kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion" 2>/dev/null)" "v$target"
    check_eq "Node $node is Ready" \
      "$(jp --request-timeout=10s node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
    check_eq "Node $node is schedulable (uncordoned)" \
      "$(jp --request-timeout=10s node "$node" '{.spec.unschedulable}')" ""
  done

  for c in kube-controller-manager kube-scheduler; do
    check_eq "$c static pod runs v$target" \
      "$(jp --request-timeout=10s -n kube-system pod "$c-$cp" '{.spec.containers[0].image}' | sed 's/.*://')" "v$target"
  done
  check_eq "kube-proxy DaemonSet runs v$target" \
    "$(jp --request-timeout=10s -n kube-system ds kube-proxy '{.spec.template.spec.containers[0].image}' | sed 's/.*://')" "v$target"
}

lab_cleanup() {
  echo "  The upgrade cannot be undone. To start over with v1.35, recreate the cluster:"
  echo "    ./scripts/init-cluster.sh --profile ops --recreate"
}
