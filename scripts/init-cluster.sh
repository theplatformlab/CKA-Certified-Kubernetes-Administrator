#!/bin/bash
# CKA practice cluster — creates a local Kubernetes cluster with kind.
# Requires: Docker (running), kubectl, curl.
#
# Usage:
#   ./scripts/init-cluster.sh                     # 'practice' profile -> cluster 'cka-practice'
#   ./scripts/init-cluster.sh --profile ops       # control-plane work + kubeadm upgrade -> 'cka-ops'
#   ./scripts/init-cluster.sh --profile cni       # no CNI installed (exercise 27) -> 'cka-cni'
#   ./scripts/init-cluster.sh --profile runtime   # cri-dockerd labs (18, 26) -> 'cka-runtime'
#   ./scripts/init-cluster.sh --recreate          # Delete and recreate the cluster
#   CLUSTER_NAME=my-lab ./scripts/init-cluster.sh # Override the cluster name
#   ./scripts/init-cluster.sh --help              # Show help
#
# After creation, run: source ./scripts/exam-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROFILE="practice"
KIND_VERSION="${KIND_VERSION:-v0.31.0}"
KUBE_VERSION="${KUBE_VERSION:-v1.35.1}"  # v1.35+ for native sidecar exercises
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

RECREATE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --recreate) RECREATE=true ;;
    --profile)
      PROFILE="${2:-}"
      shift
      ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1 (try --help)" >&2
      exit 1
      ;;
  esac
  shift
done

CONFIG_FILE="${SCRIPT_DIR}/config/${PROFILE}.yaml"
if [[ ! -f "$CONFIG_FILE" ]]; then
  log_error "Unknown profile '${PROFILE}' (expected: practice, ops, cni, runtime)"
  exit 1
fi
CLUSTER_NAME="${CLUSTER_NAME:-$(cluster_name "$PROFILE")}"

# Check if a command exists
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "'$1' is required but not installed."
    if [[ "$1" == "docker" ]]; then
      echo "  Install: https://docs.docker.com/get-docker/" >&2
    elif [[ "$1" == "kubectl" ]]; then
      echo "  Install: https://kubernetes.io/docs/tasks/tools/" >&2
    fi
    exit 1
  fi
}

# Install kind if not present
install_kind() {
  local os arch url
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      log_error "Unsupported architecture: $arch"
      exit 1
      ;;
  esac

  mkdir -p "$INSTALL_DIR"
  url="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${os}-${arch}"
  
  log_info "Installing kind ${KIND_VERSION} to ${INSTALL_DIR}/kind ..."
  if ! curl -fsSL "$url" -o "${INSTALL_DIR}/kind"; then
    log_error "Failed to download kind from $url"
    exit 1
  fi
  chmod +x "${INSTALL_DIR}/kind"
  
  # Add to PATH if not already there
  if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    export PATH="${INSTALL_DIR}:$PATH"
    log_info "Added ${INSTALL_DIR} to PATH (this session only)"
    log_warn "To make permanent, add to ~/.bashrc: export PATH=\"${INSTALL_DIR}:\$PATH\""
  fi
}

# Ensure kind is available
ensure_kind() {
  if command -v kind >/dev/null 2>&1; then
    return
  fi
  install_kind
  need_cmd kind
}

# Ensure Docker is running
ensure_docker() {
  need_cmd docker
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker is installed but not reachable. Start Docker and retry."
    exit 1
  fi
}

# ops profile: add the pkgs.k8s.io apt repo for the NEXT minor version on every
# node so the kubeadm upgrade can be done the same way as on a real kubeadm
# cluster (apt-get install kubeadm=... / kubeadm upgrade apply ...).
# The control plane also gets etcdctl for backup/restore tasks.
prepare_ops_nodes() {
  local minor next_minor node
  minor="${KUBE_VERSION#v}"
  minor="${minor%.*}"
  next_minor="v${minor%%.*}.$(( ${minor#*.} + 1 ))"

  log_info "Adding Kubernetes ${next_minor} apt repository to all nodes ..."
  for node in $(kind get nodes --name "$CLUSTER_NAME"); do
    log_info "  ${node}"
    node_exec "$node" "
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq curl gpg vim less >/dev/null
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://pkgs.k8s.io/core:/stable:/${next_minor}/deb/Release.key \\
        | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${next_minor}/deb/ /' \\
        > /etc/apt/sources.list.d/kubernetes.list
      apt-get update -qq
    "
  done

  node="${CLUSTER_NAME}-control-plane"
  log_info "Installing etcdctl on ${node} ..."
  node_exec "$node" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq etcd-client >/dev/null"
  log_info "Upgrade target versions available: $(node_exec "$node" "apt-cache madison kubeadm | awk '{print \$3}' | head -3 | tr '\n' ' '")"
}

# Each kind node uses several inotify instances; the common default of 128 is
# exhausted by ~2 clusters and containerd then fails with "too many open files".
check_inotify() {
  local instances
  instances="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"
  if (( instances > 0 && instances < 512 )); then
    log_warn "fs.inotify.max_user_instances is ${instances}; running several kind clusters needs >= 512."
    echo "  Fix: echo -e 'fs.inotify.max_user_instances=1024\\nfs.inotify.max_user_watches=1048576' | sudo tee /etc/sysctl.d/99-kind.conf && sudo sysctl --system" >&2
  fi
}

# Configure kubeconfig
configure_kubeconfig() {
  mkdir -p "$HOME/.kube"
  kind export kubeconfig --name "$CLUSTER_NAME"
  kubectl config use-context "kind-${CLUSTER_NAME}"
}

main() {
  need_cmd kubectl
  ensure_docker
  ensure_kind
  check_inotify

  # Check if cluster already exists
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    if [[ "$RECREATE" == true ]]; then
      log_info "Deleting existing cluster '${CLUSTER_NAME}' ..."
      kind delete cluster --name "$CLUSTER_NAME"
    else
      log_info "Cluster '${CLUSTER_NAME}' already exists."
      configure_kubeconfig
      kubectl cluster-info
      echo ""
      log_info "Cluster ready."
      echo ""
      echo "Next steps:"
      echo "  1. source ./scripts/exam-setup.sh  (load aliases)"
      echo "  2. k create ns exercise-01          (start first exercise)"
      exit 0
    fi
  fi

  # Create cluster with specific Kubernetes version
  echo ""
  log_info "Creating kind cluster '${CLUSTER_NAME}' (profile: ${PROFILE}) with Kubernetes ${KUBE_VERSION} ..."
  log_info "(This may take 1-2 minutes on first run)"
  echo ""
  
  local wait_args=(--wait 300s)
  # Without a CNI the nodes never become Ready, so don't wait for them.
  [[ "$PROFILE" == "cni" ]] && wait_args=()

  kind create cluster \
    --name "$CLUSTER_NAME" \
    --image "kindest/node:${KUBE_VERSION}" \
    --config "$CONFIG_FILE" \
    "${wait_args[@]}"

  configure_kubeconfig

  if [[ "$PROFILE" == "ops" ]]; then
    prepare_ops_nodes
  fi

  echo ""
  log_info "Cluster ready!"
  kubectl cluster-info
  kubectl get nodes -o wide
  
  echo ""
  echo "📌 Context: kind-${CLUSTER_NAME}"
  echo "📌 Next steps:"
  echo "   1. source ./scripts/exam-setup.sh  (load aliases + completion)"
  echo "   2. k get nodes                      (verify setup)"
  echo "   3. k create ns exercise-01          (start first exercise)"
  echo ""
  log_warn "To delete this cluster later: kind delete cluster --name ${CLUSTER_NAME}"
}

main "$@"
