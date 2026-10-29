#!/bin/bash
# Exercise runner — prepares an exercise and validates your solution.
#
# Usage:
#   ./scripts/lab.sh list              # All exercises with their cluster
#   ./scripts/lab.sh setup 07          # Create the starting state (namespace, broken objects, ...)
#   ./scripts/lab.sh check 07          # Validate the end state of your solution
#   ./scripts/lab.sh cleanup 07        # Remove everything the exercise created
#
# Each exercise has exercises/<NN>-<name>/lab.sh defining:
#   LAB_CLUSTER   cluster profile (practice | ops | cni | runtime), default practice
#   lab_setup     optional
#   lab_check     required — uses the helpers from scripts/lib/check.sh
#   lab_cleanup   optional
# The commands always target that cluster's context, whatever your current context is.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/check.sh
source "$SCRIPT_DIR/lib/check.sh"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

find_exercise() {
  local num dir
  num="$(printf "%02d" "$((10#$1))")"
  for dir in "$REPO_ROOT"/exercises/"${num}"-*/; do
    [[ -d "$dir" ]] && { echo "${dir%/}"; return 0; }
  done
  log_error "Exercise $num not found"
  return 1
}

load_exercise() {
  EXERCISE_DIR="$(find_exercise "$1")"
  if [[ ! -f "$EXERCISE_DIR/lab.sh" ]]; then
    log_error "$(basename "$EXERCISE_DIR") has no lab.sh (no automated setup/check)"
    exit 1
  fi
  LAB_CLUSTER="practice"
  unset -f lab_setup lab_check lab_cleanup 2>/dev/null || true
  # shellcheck disable=SC1091
  source "$EXERCISE_DIR/lab.sh"

  local name
  name="$(cluster_name "$LAB_CLUSTER")"
  if ! cluster_exists "$name"; then
    log_error "Cluster '$name' does not exist."
    if [[ "$LAB_CLUSTER" == "practice" ]]; then
      echo "  Create it: ./scripts/init-cluster.sh" >&2
    else
      echo "  Create it: ./scripts/init-cluster.sh --profile $LAB_CLUSTER" >&2
    fi
    exit 1
  fi
  use_cluster "$name"
}

cmd_list() {
  local dir cluster
  printf "%-4s %-40s %-9s %s\n" "#" "EXERCISE" "CLUSTER" "VALIDATOR"
  for dir in "$REPO_ROOT"/exercises/[0-9]*-*/; do
    dir="${dir%/}"
    if [[ -f "$dir/lab.sh" ]]; then
      cluster="$(sed -n 's/^LAB_CLUSTER=\([a-z]*\).*/\1/p' "$dir/lab.sh")"
      printf "%-4s %-40s %-9s %s\n" "$(basename "$dir" | cut -d- -f1)" "$(basename "$dir" | cut -d- -f2-)" "${cluster:-practice}" "yes"
    else
      printf "%-4s %-40s %-9s %s\n" "$(basename "$dir" | cut -d- -f1)" "$(basename "$dir" | cut -d- -f2-)" "-" "no"
    fi
  done
}

main() {
  local action="${1:-}"
  case "$action" in
    list) cmd_list; return ;;
    setup|check|cleanup) ;;
    -h|--help|"") usage; return ;;
    *) log_error "Unknown action: $action"; usage; exit 1 ;;
  esac
  [[ -n "${2:-}" ]] || { log_error "Missing exercise number"; exit 1; }
  load_exercise "$2"

  echo -e "${BLUE}${BOLD}$(basename "$EXERCISE_DIR")${NC} — $action (context: ${CTX})"
  case "$action" in
    setup)
      # A previous cleanup may still be deleting the namespace.
      if [[ -n "${NS:-}" ]] && [[ "$(kc get ns "$NS" -o jsonpath='{.status.phase}' 2>/dev/null)" == Terminating ]]; then
        log_info "Waiting for namespace $NS to finish terminating ..."
        kc wait --for=delete "namespace/$NS" --timeout=180s >/dev/null 2>&1 || true
      fi
      if declare -F lab_setup >/dev/null; then lab_setup; else echo "  Nothing to set up."; fi
      log_info "Ready. Work in context ${CTX}:  kubectl config use-context ${CTX}"
      ;;
    check)
      # Checks must run to the end: a failing query is a failed check, not an abort.
      set +eo pipefail
      lab_check
      check_summary
      ;;
    cleanup)
      if declare -F lab_cleanup >/dev/null; then lab_cleanup; else echo "  Nothing to clean up."; fi
      log_info "Cleaned up."
      ;;
  esac
}

main "$@"
