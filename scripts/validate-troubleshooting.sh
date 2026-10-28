#!/bin/bash
# validate-troubleshooting.sh — Verify troubleshooting exercise quality and readiness
# Updated May 2026 with trap architecture validation
# 
# Usage: bash scripts/validate-troubleshooting.sh [exercise-num]
# Ex:    bash scripts/validate-troubleshooting.sh 11
#        bash scripts/validate-troubleshooting.sh        (checks all troubleshooting exercises)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXERCISES_DIR="$REPO_ROOT/exercises"

# Troubleshooting exercise numbers
TROUBLESHOOTING_EXERCISES=(11 29)

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  return 1
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

# Validate single troubleshooting exercise
validate_exercise() {
  local num="$1"
  local ex_dir="$EXERCISES_DIR/$(printf "%02d" "$num")-*/README.md"
  ex_dir=$(ls "$ex_dir" 2>/dev/null | head -1)

  if [[ ! -f "$ex_dir" ]]; then
    log_fail "Exercise $(printf "%02d" "$num") README not found"
    return 1
  fi

  local ex_path=$(dirname "$ex_dir")
  local ex_name=$(basename "$ex_path")
  echo ""
  echo "Validating: $ex_name"
  echo "---"

  local errors=0

  # Check 1: Conventions block exists
  if grep -q "^## Conventions" "$ex_dir"; then
    log_pass "Conventions block present"
  else
    log_fail "Missing Conventions block (should define Primary/Secondary traps)"
    ((errors++))
  fi

  # Check 2: What tripped me up section with at least one trap/gotcha
  if grep -q "^## What tripped me up" "$ex_dir"; then
    local gotcha_count=$(grep -c "**.*Trap" "$ex_dir" || true)
    local gotcha_v1_35=$(grep -c "v1.35" "$ex_dir" || true)
    
    if [[ $gotcha_count -ge 2 ]]; then
      log_pass "Multiple trap/gotcha entries documented ($gotcha_count found)"
    else
      log_warn "Only $gotcha_count trap/gotcha documented (recommend 2+)"
      ((errors++))
    fi

    if [[ $gotcha_v1_35 -ge 1 ]]; then
      log_pass "v1.35-specific gotchas documented"
    else
      log_warn "No v1.35-specific gotchas found (May 2026 update)"
      ((errors++))
    fi
  else
    log_fail "Missing 'What tripped me up' section with gotchas"
    ((errors++))
  fi

  # Check 3: Verify section exists
  if grep -q "^## Verify" "$ex_dir"; then
    log_pass "Verification steps present"
  else
    log_fail "Missing Verify section (no validation criteria)"
    ((errors++))
  fi

  # Check 4: Solution section exists (optional but recommended)
  if grep -q "^## Cleanup\|^<details>" "$ex_dir"; then
    log_pass "Solution/cleanup section present"
  else
    log_warn "No Solution section (helpful but not required)"
  fi

  # Check 5: Markdown syntax (no orphaned backticks)
  local unclosed_backticks=$(grep -o '`' "$ex_dir" | wc -l)
  if (( unclosed_backticks % 2 == 0 )); then
    log_pass "Markdown backticks balanced"
  else
    log_fail "Unbalanced backticks in markdown"
    ((errors++))
  fi

  # Check 6: Hints section exists
  if grep -q "<details>" "$ex_dir"; then
    log_pass "Hints/solution in collapsible format"
  else
    log_warn "No collapsible hints section found"
  fi

  return $errors
}

# Main
main() {
  local target="$1"
  local count=0

  if [[ -z "$target" ]]; then
    # Validate all troubleshooting exercises
    echo "Validating all troubleshooting exercises (May 2026)..."
    for num in "${TROUBLESHOOTING_EXERCISES[@]}"; do
      if validate_exercise "$num"; then
        ((count++))
      fi
    done
    echo ""
    echo "---"
    echo "Summary: $count/${#TROUBLESHOOTING_EXERCISES[@]} exercises validated"
    if [[ $count -eq ${#TROUBLESHOOTING_EXERCISES[@]} ]]; then
      log_pass "All troubleshooting exercises ready for exam!"
    else
      log_warn "Some exercises need enhancement"
      exit 1
    fi
  else
    # Validate specific exercise
    validate_exercise "$target"
  fi
}

main "$@"
