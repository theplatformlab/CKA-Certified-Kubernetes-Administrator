# shellcheck shell=bash
# Shared helpers for init-cluster.sh, lab.sh and mock-exam.sh.
# Source it; do not execute it.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Cluster profiles. Each profile maps to a kind config in scripts/config/
# and a default cluster name, overridable via environment variables
# (the mock exam uses this to run against its own clusters).
cluster_name() {
  case "$1" in
    practice) echo "${CKA_PRACTICE_CLUSTER:-cka-practice}" ;;
    ops)      echo "${CKA_OPS_CLUSTER:-cka-ops}" ;;
    cni)      echo "${CKA_CNI_CLUSTER:-cka-cni}" ;;
    runtime)  echo "${CKA_RUNTIME_CLUSTER:-cka-runtime}" ;;
    *) log_error "Unknown cluster profile: $1"; return 1 ;;
  esac
}

cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "$1"
}

# Select the cluster all following kc/node_* calls talk to.
use_cluster() {
  CLUSTER="$1"
  CTX="kind-${CLUSTER}"
}

# kubectl against the selected cluster, independent of the current context.
kc() {
  kubectl --context "$CTX" "$@"
}

# Node names of the selected cluster (kind naming: <cluster>-control-plane,
# <cluster>-worker, <cluster>-worker2, ...).
control_plane_node() { echo "${CLUSTER}-control-plane"; }
worker_node() { if [[ "${1:-1}" == 1 ]]; then echo "${CLUSTER}-worker"; else echo "${CLUSTER}-worker$1"; fi; }

# Run a shell command on a node (kind nodes are containers).
node_exec() {
  local node="$1"; shift
  docker exec "$node" bash -c "$*"
}
