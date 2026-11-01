#!/bin/bash
# Item runner — prepares an exercise or pool question and validates your solution.
# (The interactive way is ./cka; this is the scriptable layer underneath.)
#
# Usage:
#   ./scripts/lab.sh list                     # All items with their cluster
#   ./scripts/lab.sh setup 07                 # Exercise 07: create the starting state
#   ./scripts/lab.sh check 07                 # Validate the end state of your solution
#   ./scripts/lab.sh cleanup 07               # Remove everything the item created
#   ./scripts/lab.sh setup rollout-rollback   # Pool questions are addressed by id
#   ./scripts/lab.sh params rollout-rollback  # Print the item's parameters (KEY=VALUE)
#
# Each item directory (exercises/<NN>-<name>/ or questions/<id>/) has a lab.sh defining:
#   LAB_CLUSTER   cluster profile (practice | ops | cni | runtime), default practice
#   lab_params    optional — prints KEY=VALUE lines (see scripts/lib/params.sh)
#   lab_setup     optional
#   lab_check     required — uses the helpers from scripts/lib/check.sh
#   lab_cleanup   optional
# The commands always target that cluster's context, whatever your current context is.
#
# Environment (set by ./cka, defaults for manual use):
#   WORKDIR        directory for answer files (default ~/cka-lab/<item-id>)
#   CKA_SEED       seed for lab_params (default 1, so manual runs are repeatable)
#   CKA_PARAMS     set to 1 when the parameters are already in the environment
#   ITEM_NS        exams only: namespace replacing an exercise's exercise-NN

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/check.sh
source "$SCRIPT_DIR/lib/check.sh"
# shellcheck source=lib/params.sh
source "$SCRIPT_DIR/lib/params.sh"

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

# find_item <NN | question-id | path> -> item directory
find_item() {
  local spec="$1" dir
  if [[ -d "$spec" && -f "$spec/lab.sh" ]]; then
    (cd "$spec" && pwd); return 0
  fi
  if [[ "$spec" =~ ^[0-9]+$ ]]; then
    for dir in "$REPO_ROOT"/exercises/"$(printf "%02d" "$((10#$spec))")"-*/; do
      [[ -d "$dir" ]] && { echo "${dir%/}"; return 0; }
    done
  fi
  [[ -d "$REPO_ROOT/questions/$spec" ]] && { echo "$REPO_ROOT/questions/$spec"; return 0; }
  log_error "Item '$spec' not found (exercise number, question id or directory)"
  return 1
}

item_id() {
  local dir="$1"
  if [[ "$dir" == */exercises/* ]]; then echo "ex$(basename "$dir" | cut -d- -f1)"; else basename "$dir"; fi
}

load_item() {
  EXERCISE_DIR="$(find_item "$1")"
  export ITEM_DIR="$EXERCISE_DIR"
  export WORKDIR="${WORKDIR:-$HOME/cka-lab/$(item_id "$EXERCISE_DIR")}"
  LAB_CLUSTER="practice"
  unset -f lab_params lab_setup lab_check lab_cleanup 2>/dev/null || true
  # shellcheck disable=SC1091
  source "$EXERCISE_DIR/lab.sh"
}

print_params() {
  declare -F lab_params >/dev/null || return 0
  CKA_RNG_FILE="$(mktemp)"
  export CKA_RNG_FILE
  echo "${CKA_SEED:-1}:$(basename "$EXERCISE_DIR") 0" >"$CKA_RNG_FILE"
  lab_params
  rm -f "$CKA_RNG_FILE"
}

# Export the item's parameters unless the caller already did.
load_params() {
  [[ "${CKA_PARAMS:-}" == 1 ]] && return 0
  local line
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] && export "${line?}"
  done < <(print_params)
}

# Namespaces declared in item.yaml ({{PARAM}} placeholders filled from the env).
item_namespaces() {
  local ns var
  [[ -f "$EXERCISE_DIR/item.yaml" ]] || return 0
  sed -n 's/^namespaces: *\[\(.*\)\]/\1/p' "$EXERCISE_DIR/item.yaml" | tr ',' '\n' | while read -r ns; do
    while [[ "$ns" =~ \{\{([A-Z][A-Z0-9_]*)\}\} ]]; do
      var="${BASH_REMATCH[1]}"
      ns="${ns//\{\{$var\}\}/${!var:-}}"
    done
    # In exams an exercise's exercise-NN namespaces get the exam name (ITEM_NS).
    [[ -n "${ITEM_NS:-}" ]] && ns="${ns/exercise-[0-9][0-9]/$ITEM_NS}"
    [[ -n "$ns" ]] && echo "$ns"
  done
}

# Every item's namespaces go away on cleanup (items without own lab_cleanup
# rely on this; for the others it's a no-op).
delete_item_namespaces() {
  local ns
  for ns in $(item_namespaces); do
    case "$ns" in default|kube-*) continue ;; esac
    kc delete namespace "$ns" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
  done
}

require_cluster() {
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
  printf "%-30s %-42s %-9s\n" "ID" "DIRECTORY" "CLUSTER"
  for dir in "$REPO_ROOT"/exercises/[0-9]*-*/ "$REPO_ROOT"/questions/*/; do
    dir="${dir%/}"
    [[ -f "$dir/lab.sh" ]] || continue
    cluster="$(sed -n 's/^LAB_CLUSTER=\([a-z]*\).*/\1/p' "$dir/lab.sh")"
    printf "%-30s %-42s %-9s\n" "$(item_id "$dir")" "${dir#"$REPO_ROOT"/}" "${cluster:-practice}"
  done
}

main() {
  local action="${1:-}"
  case "$action" in
    list) cmd_list; return ;;
    setup|check|cleanup|params) ;;
    -h|--help|"") usage; return ;;
    *) log_error "Unknown action: $action"; usage; exit 1 ;;
  esac
  [[ -n "${2:-}" ]] || { log_error "Missing item (exercise number or question id)"; exit 1; }
  load_item "$2"
  if [[ "$action" == params ]]; then
    print_params
    return
  fi
  load_params
  require_cluster

  echo -e "${BLUE}${BOLD}$(basename "$EXERCISE_DIR")${NC} — $action (context: ${CTX})"
  case "$action" in
    setup)
      # A previous cleanup may still be deleting the namespaces.
      local ns
      for ns in ${NS:-} $(item_namespaces); do
        if [[ "$(kc get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)" == Terminating ]]; then
          log_info "Waiting for namespace $ns to finish terminating ..."
          kc wait --for=delete "namespace/$ns" --timeout=180s >/dev/null 2>&1 || true
        fi
      done
      mkdir -p "$WORKDIR"
      if declare -F lab_setup >/dev/null; then lab_setup; else echo "  Nothing to set up."; fi
      log_info "Ready. Work in context ${CTX}:  kubectl config use-context ${CTX}"
      ;;
    check)
      # Checks must run to the end: a failing query is a failed check, not an abort.
      set +eo pipefail
      # kubectl retries for ~50s against an API server that is down, which
      # made grading crawl through every query; probe once and let every kc
      # call fail right away instead.
      if ! timeout 20 kubectl --context "$CTX" get --raw /version >/dev/null 2>&1; then
        log_warn "API server of ${CLUSTER} does not answer: every check that needs it fails"
        kc() { return 1; }
      fi
      lab_check
      check_summary
      ;;
    cleanup)
      if declare -F lab_cleanup >/dev/null; then lab_cleanup; fi
      delete_item_namespaces
      log_info "Cleaned up."
      ;;
  esac
}

main "$@"
