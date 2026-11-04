#!/bin/bash
# CKA practice cluster — creates a local Kubernetes cluster with kind.
# Requires: Docker (running), kubectl, curl.
#
# Usage:
#   ./scripts/init-cluster.sh                     # 'practice' profile -> cluster 'cka-practice'
#   ./scripts/init-cluster.sh --profile ops       # control-plane work + kubeadm upgrade -> 'cka-ops'
#   ./scripts/init-cluster.sh --profile cni       # no CNI installed (you install Calico) -> 'cka-cni'
#   ./scripts/init-cluster.sh --profile runtime   # Docker Engine + cri-dockerd tasks -> 'cka-runtime'
#   ./scripts/init-cluster.sh --profile ha        # 3 control planes + 1 worker -> 'cka-ha'
#   ./scripts/init-cluster.sh --profile cks       # CKS: security tooling on the nodes -> 'cka-cks'
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
KUBE_VERSION="${KUBE_VERSION:-v1.35.1}"  # v1.35+ for native sidecar tasks
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
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
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
  log_error "Unknown profile '${PROFILE}' (expected: practice, ops, cni, runtime, ha, cks)"
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

# Every node gets the editors and pager you have on the real exam's nodes
# (kind's node image ships none of them). Nodes are set up in parallel.
install_node_tools() {
  local node pids=() failed=0
  log_info "Installing vim, nano and less on all nodes ..."
  for node in $(kind get nodes --name "$CLUSTER_NAME"); do
    [[ "$node" == *external-load-balancer ]] && continue
    node_exec "$node" "export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq && apt-get install -y -qq vim nano less >/dev/null" >/dev/null 2>&1 &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  (( failed )) && log_warn "Some nodes could not install the editors (no internet access?)"
  return 0
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
    # The HA load balancer is an haproxy container without bash or apt.
    [[ "$node" == *external-load-balancer ]] && continue
    log_info "  ${node}"
    node_exec "$node" "
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq curl gpg sudo openssl >/dev/null
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://pkgs.k8s.io/core:/stable:/${next_minor}/deb/Release.key \\
        | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${next_minor}/deb/ /' \\
        > /etc/apt/sources.list.d/kubernetes.list
      apt-get update -qq
      # kind ships its own /etc/default/kubelet; keep it when the kubelet
      # package is upgraded instead of stopping at a dpkg conffile prompt.
      printf 'Dpkg::Options { \"--force-confdef\"; \"--force-confold\"; };\\n' > /etc/apt/apt.conf.d/90-keep-config
    "
  done

  for node in $(kind get nodes --name "$CLUSTER_NAME"); do
    [[ "$node" == *control-plane* ]] || continue
    log_info "Installing etcdctl on ${node} ..."
    node_exec "$node" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq etcd-client >/dev/null"
  done
  node="${CLUSTER_NAME}-control-plane"
  log_info "Upgrade target versions available: $(node_exec "$node" "apt-cache madison kubeadm | awk '{print \$3}' | head -3 | tr '\n' ' '")"
}

# cks profile: the tools the CKS exam provides on its nodes.
#   every node:     kube-bench (/etc/kube-bench/cfg), apparmor (apparmor_parser,
#                   aa-status; profiles only load if the host kernel has the
#                   AppArmor LSM active, see docs/cks-wsl.md)
#   control plane:  trivy (vulnerability DB pre-downloaded) and kubesec
#   workers:        Falco as systemd service 'falco' (modern eBPF driver,
#                   rules in /etc/falco, alerts in journalctl -u falco), and
#                   gVisor (runsc) with the containerd runtime handler 'runsc'
# Versions can be pinned with the environment variables below. Nodes are set
# up in parallel; each node's log goes to a temp file shown on failure.
TRIVY_VERSION="${TRIVY_VERSION:-0.76.1}"
KUBE_BENCH_VERSION="${KUBE_BENCH_VERSION:-0.16.0}"
KUBESEC_VERSION="${KUBESEC_VERSION:-2.15.0}"

cks_node_common() {
  cat <<EOF
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl gpg ca-certificates apparmor >/dev/null
cd /tmp
curl -fsSLo kube-bench.deb https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_linux_amd64.deb
apt-get install -y -qq ./kube-bench.deb >/dev/null
rm -f kube-bench.deb
# kind's policy-rc.d keeps apt from starting or stopping services (useful in
# image builds). Real nodes have none: 'apt-get purge' must stop the service.
rm -f /usr/sbin/policy-rc.d
EOF
}

cks_control_plane() {
  cat <<EOF
curl -fsSLo trivy.deb https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb
apt-get install -y -qq ./trivy.deb >/dev/null
rm -f trivy.deb
curl -fsSL https://github.com/controlplaneio/kubesec/releases/download/v${KUBESEC_VERSION}/kubesec_linux_amd64.tar.gz | tar xz -C /usr/local/bin kubesec
# The DB download takes a while; do it now so scans start right away.
trivy image --download-db-only -q
EOF
}

cks_worker() {
  cat <<'EOF'
# Falco from the falcosecurity apt repo, modern eBPF driver (needs a kernel
# with BTF; no kernel module or headers). The package installs the unit as
# falco-modern-bpf.service with an alias 'falco'; journalctl -u needs the
# real unit name, so it runs as a plain falco.service instead.
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --dearmor --yes -o /usr/share/keyrings/falco-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main' > /etc/apt/sources.list.d/falcosecurity.list
# gVisor from its apt repo (runsc + containerd-shim-runsc-v1)
curl -fsSL https://gvisor.dev/archive.key | gpg --dearmor --yes -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main' > /etc/apt/sources.list.d/gvisor.list
apt-get update -qq
FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf FALCOCTL_ENABLED=no \
  apt-get install -y -qq falco runsc >/dev/null 2>&1
systemctl disable --now falco-modern-bpf >/dev/null 2>&1 || true
rm -f /etc/systemd/system/falco.service
sed '/^Alias=/d; s/^Description=.*/Description=Falco: Container Native Runtime Security (modern eBPF)/' \
  /usr/lib/systemd/system/falco-modern-bpf.service > /etc/systemd/system/falco.service
systemctl daemon-reload
systemctl enable --now falco >/dev/null 2>&1
if ! grep -q 'runtimes.runsc\]' /etc/containerd/config.toml; then
  cat >> /etc/containerd/config.toml <<'TOML'

# gVisor: RuntimeClass handler "runsc"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
TOML
  systemctl restart containerd
fi
for i in $(seq 30); do systemctl is-active -q falco && break; sleep 1; done
systemctl is-active -q falco
EOF
}

prepare_cks_nodes() {
  local node script log pids=() nodes=() logs=() i failed=0
  log_info "Installing CKS tooling (kube-bench, trivy, kubesec, Falco, gVisor) ..."
  for node in $(kind get nodes --name "$CLUSTER_NAME"); do
    script="$(cks_node_common)"
    if [[ "$node" == *control-plane* ]]; then
      script+=$'\n'"$(cks_control_plane)"
    else
      script+=$'\n'"$(cks_worker)"
    fi
    log="$(mktemp)"
    node_exec "$node" "$script" >"$log" 2>&1 &
    pids+=($!); nodes+=("$node"); logs+=("$log")
  done
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      log_info "  ${nodes[$i]}: done"
    else
      failed=1
      log_error "  ${nodes[$i]}: tool installation failed:"
      tail -n 20 "${logs[$i]}" >&2
    fi
    rm -f "${logs[$i]}"
  done
  (( failed )) && return 1

  if [[ "$(node_exec "${CLUSTER_NAME}-worker" 'cat /sys/module/apparmor/parameters/enabled 2>/dev/null')" != Y ]]; then
    log_warn "AppArmor is not active in the host kernel: AppArmor items will not work (see docs/cks-wsl.md)."
  fi
  return 0
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
# Adds the cluster to the kubeconfig and switches to it — unless
# CKA_KEEP_CONTEXT=1 (used by ./cka), then the previous context stays current.
#
# Several clusters can be created at the same time (./cka builds the exam
# clusters in parallel), but kind fails instead of waiting when another kind
# process holds the kubeconfig lock. So kind create/delete work on a private
# kubeconfig, and only this step touches ~/.kube/config — under a flock.
configure_kubeconfig() {
  mkdir -p "$HOME/.kube"
  (
    flock 9
    kind export kubeconfig --name "$CLUSTER_NAME"
    if [[ "${CKA_KEEP_CONTEXT:-}" == 1 && -n "${PREVIOUS_CONTEXT:-}" ]]; then
      kubectl config use-context "$PREVIOUS_CONTEXT" >/dev/null
    else
      kubectl config use-context "kind-${CLUSTER_NAME}"
    fi
  ) 9>"$HOME/.kube/.cka-init.lock"
}

main() {
  need_cmd kubectl
  PREVIOUS_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
  KIND_KUBECONFIG="$(mktemp)"
  trap 'rm -f "$KIND_KUBECONFIG"' EXIT
  ensure_docker
  ensure_kind
  check_inotify

  # Check if cluster already exists
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    if [[ "$RECREATE" == true ]]; then
      log_info "Deleting existing cluster '${CLUSTER_NAME}' ..."
      kind delete cluster --name "$CLUSTER_NAME" --kubeconfig "$KIND_KUBECONFIG"
    else
      log_info "Cluster '${CLUSTER_NAME}' already exists."
      configure_kubeconfig
      kubectl --context "kind-${CLUSTER_NAME}" cluster-info || true
      echo ""
      log_info "Cluster ready."
      echo ""
      echo "Next steps:"
      echo "  1. source ./scripts/exam-setup.sh  (load aliases)"
      echo "  2. ./cka                           (start the lab)"
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
    --kubeconfig "$KIND_KUBECONFIG" \
    --name "$CLUSTER_NAME" \
    --image "kindest/node:${KUBE_VERSION}" \
    --config "$CONFIG_FILE" \
    "${wait_args[@]}"

  configure_kubeconfig

  install_node_tools

  # ha nodes get the same tooling (etcdctl for member/health checks).
  if [[ "$PROFILE" == "ops" || "$PROFILE" == "ha" ]]; then
    prepare_ops_nodes
  fi
  if [[ "$PROFILE" == "cks" ]]; then
    prepare_cks_nodes
  fi

  echo ""
  log_info "Cluster ready!"
  kubectl --context "kind-${CLUSTER_NAME}" cluster-info || true
  kubectl --context "kind-${CLUSTER_NAME}" get nodes -o wide || true
  
  echo ""
  echo "📌 Context: kind-${CLUSTER_NAME}"
  echo "📌 Next steps:"
  echo "   1. source ./scripts/exam-setup.sh  (load aliases + completion)"
  echo "   2. k get nodes                      (verify setup)"
  echo "   3. ./cka                           (start the lab)"
  echo ""
  log_warn "To delete this cluster later: kind delete cluster --name ${CLUSTER_NAME}"
}

main "$@"
