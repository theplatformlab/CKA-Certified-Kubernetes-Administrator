# shellcheck shell=bash
# Assertion helpers for exercise and mock exam validators.
# Requires common.sh (kc, node_exec) to be sourced first.
#
# Every helper prints one ✓/✗ line and updates the counters; none of them
# abort on failure, so a check function always runs to the end.

CHECK_PASS=0
CHECK_FAIL=0

check_reset() { CHECK_PASS=0; CHECK_FAIL=0; }

_pass() { CHECK_PASS=$((CHECK_PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
_fail() {
  CHECK_FAIL=$((CHECK_FAIL + 1))
  echo -e "  ${RED}✗${NC} $1"
  [[ -n "${2:-}" ]] && echo -e "      ${YELLOW}$2${NC}"
  return 0
}

# check "description" command [args...]
# Passes when the command exits 0. Output of the command is discarded.
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _pass "$desc"; else _fail "$desc"; fi
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
# Runs a throwaway busybox pod (optionally labelled, e.g. "app=client,tier=web")
# and executes <command> in it with sh -c. Returns the command's exit code.
# Used for connectivity and DNS tests.
probe() {
  local ns="$1" labels="$2" cmd="$3"
  local name="probe-$RANDOM$RANDOM"
  local args=(-n "$ns" run "$name" --image=busybox:1.37 --restart=Never --quiet --rm -i
              --pod-running-timeout=60s --command)
  [[ "$labels" != "-" ]] && args+=(--labels="$labels")
  timeout 90 kubectl --context "$CTX" "${args[@]}" -- sh -c "$cmd" </dev/null 2>/dev/null
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
