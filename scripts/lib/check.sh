# shellcheck shell=bash
# Assertion helpers for exercise and mock exam validators.
# Requires common.sh (kc, node_exec) to be sourced first.
#
# Every helper prints one ✓/✗ line and updates the counters; none of them
# abort on failure, so a check function always runs to the end.
# If CKA_RESULTS_FILE is set, every result is also appended to it as
# "PASS<TAB>description" or "FAIL<TAB>description<TAB>detail" (read by ./cka).

CHECK_PASS=0
CHECK_FAIL=0
CHECK_GATE=""

check_reset() { CHECK_PASS=0; CHECK_FAIL=0; CHECK_GATE=""; }

_pass() {
  # After a failed gate nothing else earns points (no credit for "X is not
  # allowed" style checks when the task wasn't attempted).
  if [[ -n "$CHECK_GATE" ]]; then _fail "$1" "not graded: requires '$CHECK_GATE'"; return 0; fi
  CHECK_PASS=$((CHECK_PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"
  [[ -n "${CKA_RESULTS_FILE:-}" ]] && printf 'PASS\t%s\n' "$1" >>"$CKA_RESULTS_FILE"
  return 0
}
_fail() {
  CHECK_FAIL=$((CHECK_FAIL + 1))
  echo -e "  ${RED}✗${NC} $1"
  [[ -n "${2:-}" ]] && echo -e "      ${YELLOW}$2${NC}"
  [[ -n "${CKA_RESULTS_FILE:-}" ]] && printf 'FAIL\t%s\t%s\n' "$1" "${2:-}" >>"$CKA_RESULTS_FILE"
  return 0
}

# check "description" command [args...]
# Passes when the command exits 0. Output of the command is discarded.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$desc"; else _fail "$desc"; fi
}

# check_gate "description" command [args...]
# Like check, but if it fails every following check of this run fails too.
# Use it for the "task was attempted" precondition (e.g. the Role exists).
check_gate() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$desc"; else _fail "$desc"; CHECK_GATE="$desc"; fi
}

# check_not "description" command [args...]  — passes when the command fails.
check_not() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _fail "$desc"; else _pass "$desc"; fi
}

# check_eq "description" "actual" "expected"
check_eq() {
  if [[ "$2" == "$3" ]]; then _pass "$1"; else _fail "$1" "expected '$3', got '${2:-<empty>}'"; fi
}

# check_match "description" "actual" "extended-regex"
check_match() {
  if [[ "$2" =~ $3 ]]; then _pass "$1"; else _fail "$1" "expected to match /$3/, got '${2:-<empty>}'"; fi
}

# check_contains "description" "haystack" "needle"
check_contains() {
  if [[ "$2" == *"$3"* ]]; then _pass "$1"; else _fail "$1" "expected to contain '$3'"; fi
}

# jp <kc get args...> <jsonpath>  — shorthand for a jsonpath query; empty on error.
# Example: jp -n ex01 pod web '{.spec.containers[0].image}'
jp() {
  local path="${*: -1}"
  kc get "${@:1:$#-1}" -o jsonpath="$path" 2>/dev/null
}

# exists <kc get args...>  — true when the object exists.
exists() { kc get "$@" >/dev/null 2>&1; }

# probe <namespace> <labels|-> <command>
# Runs a throwaway busybox pod (optionally labelled, e.g. "app=client,tier=web"),
# executes <command> in it with sh -c and prints its output. Returns 0 when the
# command succeeded. Used for connectivity and DNS tests.
# (The pod runs detached and its output is read from the logs afterwards;
# attaching with `kubectl run -i` can miss output printed right at the start.)
probe() {
  local ns="$1" labels="$2" cmd="$3"
  local name="probe-$RANDOM$RANDOM" phase="" i
  local args=(-n "$ns" run "$name" --image=busybox:1.37 --restart=Never --command)
  [[ "$labels" != "-" ]] && args+=(--labels="$labels")
  kc "${args[@]}" -- sh -c "$cmd" >/dev/null 2>&1 || return 1
  for (( i = 0; i < 180; i++ )); do
    phase="$(kc -n "$ns" get pod "$name" -o jsonpath='{.status.phase}' 2>/dev/null)"
    [[ "$phase" == Succeeded || "$phase" == Failed ]] && break
    sleep 0.5
  done
  kc -n "$ns" logs "$name" 2>/dev/null
  kc -n "$ns" delete pod "$name" --wait=false >/dev/null 2>&1
  [[ "$phase" == Succeeded ]]
}

# check_summary — prints the result line; returns 0 only if every check passed.
check_summary() {
  local total=$((CHECK_PASS + CHECK_FAIL))
  echo ""
  if (( CHECK_FAIL == 0 )); then
    echo -e "${GREEN}${BOLD}PASS${NC} — ${CHECK_PASS}/${total} checks passed"
    return 0
  fi
  echo -e "${RED}${BOLD}FAIL${NC} — ${CHECK_PASS}/${total} checks passed"
  return 1
}
