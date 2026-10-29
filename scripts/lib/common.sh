# shellcheck shell=bash
# Shared helpers for init-cluster.sh and lab.sh (and through it, ./cka).
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
    ha)       echo "${CKA_HA_CLUSTER:-cka-ha}" ;;
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
# control_plane_node_n <n> — the n-th control plane of an HA cluster (1 = first)
control_plane_node_n() { if [[ "$1" == 1 ]]; then control_plane_node; else echo "${CLUSTER}-control-plane$1"; fi; }
worker_node() { if [[ "${1:-1}" == 1 ]]; then echo "${CLUSTER}-worker"; else echo "${CLUSTER}-worker$1"; fi; }

# Run a shell command on a node (kind nodes are containers).
node_exec() {
  local node="$1"; shift
  docker exec "$node" bash -c "$*"
}

# Create a namespace if it doesn't exist yet (idempotent).
ensure_ns() {
  kc create namespace "$1" --dry-run=client -o yaml | kc apply -f - >/dev/null
}

# backup_node_file <node> <path> — keep a pristine copy of a node file (only the
# first call copies, so re-running a setup never backs up a broken file).
backup_node_file() {
  node_exec "$1" "mkdir -p /var/lib/cka-lab/backup
    f=/var/lib/cka-lab/backup/\$(echo '$2' | tr / _)
    [ -f \"\$f\" ] || cp '$2' \"\$f\""
}

# restore_node_file <node> <path> — put the pristine copy back (no-op without backup).
restore_node_file() {
  node_exec "$1" "f=/var/lib/cka-lab/backup/\$(echo '$2' | tr / _)
    if [ -f \"\$f\" ]; then cp \"\$f\" '$2' && rm -f \"\$f\"; fi"
}
