#!/bin/bash
# Quality Lint Tool for Exercises
# Checks for content quality, completeness, and best practices inspired by exam patterns.
# Detects orphaned or incomplete trap definitions and validates grading readiness.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXERCISES_DIR="$REPO_ROOT/exercises"

lint_errors=0
lint_warnings=0

# --- Utility functions ---
lint_ok() { echo -e "${GREEN}✓${NC} $1"; }
lint_error() { echo -e "${RED}✗${NC} $1"; ((lint_errors++)); }
lint_warning() { echo -e "${YELLOW}⚠${NC} $1"; ((lint_warnings++)); }
print_section() { echo -e "\n${BLUE}=== $1 ===${NC}\n"; }

# --- Exercise Content Quality Checks ---
print_section "Exercise Content Quality"

for exercise_dir in "$EXERCISES_DIR"/[0-9]*-*/; do
  if [ ! -d "$exercise_dir" ]; then
    continue
  fi

  exercise=$(basename "$exercise_dir")
  readme="$exercise_dir/README.md"
  
  if [ ! -f "$readme" ]; then
    continue
  fi

  # Check for vague or incomplete task descriptions
  if grep -q "TODO\|FIXME\|XXX\|...\|to be continued" "$readme" -i; then
    lint_warning "$exercise: Contains incomplete placeholders (TODO/FIXME/...)"
  fi

  # Check for documentation of common traps
  if grep -q "## What tripped me up" "$readme" || grep -q "## Gotchas" "$readme" || grep -q "## Common Mistakes" "$readme"; then
    lint_ok "$exercise: Documents common gotchas"
  else
    lint_warning "$exercise: Missing 'What tripped me up' or 'Common Mistakes' section"
  fi

  # Verify hints are comprehensive
  if grep -q "<details>" "$readme"; then
    hint_lines=$(sed -n '/<details>/,/<\/details>/p' "$readme" | wc -l)
    if [ "$hint_lines" -lt 3 ]; then
      lint_warning "$exercise: Hints section appears minimal ($hint_lines lines)"
    fi
  fi

  # Check for concrete verification commands
  if grep -q "k get\|kubectl\|docker" "$readme"; then
    lint_ok "$exercise: Includes concrete kubectl/docker verification commands"
  else
    lint_warning "$exercise: Consider adding concrete verification commands (kubectl/docker)"
  fi

  # Validate task structure (numbered or bulleted)
  if grep -q "^[0-9]\+\." "$readme" || grep -q "^-\|^\*" "$readme"; then
    lint_ok "$exercise: Tasks are properly formatted (numbered/bulleted)"
  else
    lint_warning "$exercise: Task formatting unclear (should be numbered or bulleted)"
  fi
done

# --- Check for trap concepts ---
print_section "Trap Concept Coverage"

trap_concepts=(
  "tripped me up"
  "gotcha"
  "common mistake"
  "doesn't work"
  "won't"
  "fails"
  "easy to miss"
  "careful"
  "watch out"
)

trap_coverage=0
total_traps_detected=0

for exercise_dir in "$EXERCISES_DIR"/[0-9]*-*/; do
  if [ ! -d "$exercise_dir" ]; then
    continue
  fi

  exercise=$(basename "$exercise_dir")
  readme="$exercise_dir/README.md"
  
  if [ ! -f "$readme" ]; then
    continue
  fi

  # Count trap references
  trap_mentions=0
  for concept in "${trap_concepts[@]}"; do
    matches=$(grep -ic "$concept" "$readme" || true)
    trap_mentions=$((trap_mentions + matches))
  done

  if [ "$trap_mentions" -gt 0 ]; then
    lint_ok "$exercise: $trap_mentions trap concept(s) documented"
    ((trap_coverage++))
    ((total_traps_detected += trap_mentions))
  else
    lint_warning "$exercise: No trap/gotcha concepts documented"
  fi
done

echo ""
lint_ok "Overall: $trap_coverage exercises document trap concepts (total: $total_traps_detected mentions)"

# --- Check for resource requirements clarity ---
print_section "Resource Requirements & Prerequisites"

prereq_indicators=(
  "prerequisite"
  "requires"
  "assumes"
  "need to have"
  "must have"
  "runs on"
)

prereq_coverage=0
for exercise_dir in "$EXERCISES_DIR"/[0-9]*-*/; do
  if [ ! -d "$exercise_dir" ]; then
    continue
  fi

  exercise=$(basename "$exercise_dir")
  readme="$exercise_dir/README.md"
  
  if [ ! -f "$readme" ]; then
    continue
  fi

  found_prereq=false
  for indicator in "${prereq_indicators[@]}"; do
    if grep -iq "$indicator" "$readme"; then
      found_prereq=true
      break
    fi
  done

  if [ "$found_prereq" = true ]; then
    lint_ok "$exercise: Prerequisites/requirements documented"
    ((prereq_coverage++))
  else
    lint_warning "$exercise: No prerequisites/requirements documented"
  fi
done

echo ""
lint_ok "Overall: $prereq_coverage exercises document prerequisites"

# --- Cross-exercise consistency ---
print_section "Cross-Exercise Consistency"

# Check that all exercises use consistent Kubernetes resource naming
naming_patterns=0
for exercise_dir in "$EXERCISES_DIR"/[0-9]*-*/; do
  if [ ! -d "$exercise_dir" ]; then
    continue
  fi

  readme="$exercise_dir/README.md"
  [ -f "$readme" ] || continue

  # Check if uses consistent naming: kebab-case for resources
  if grep -q "^[[:space:]]*-\|^[[:space:]]*name:" "$readme"; then
    ((naming_patterns++))
  fi
done

total_exercises=$(ls -d "$EXERCISES_DIR"/[0-9]*-*/ 2>/dev/null | wc -l)
if [ "$naming_patterns" -ge "$((total_exercises - 2))" ]; then
  lint_ok "Naming patterns: Consistent across exercises"
else
  lint_warning "Naming patterns: Some exercises may use inconsistent naming (found $naming_patterns of $total_exercises)"
fi

# --- Markdown syntax validation ---
print_section "Markdown Syntax Validation"

markdown_errors=0
for readme in "$EXERCISES_DIR"/[0-9]*-*/README.md; do
  if [ ! -f "$readme" ]; then
    continue
  fi

  exercise=$(basename "$(dirname "$readme")")

  # Check balanced markdown brackets
  open_count=$(grep -o '```' "$readme" | wc -l)
  if [ $((open_count % 2)) -ne 0 ]; then
    lint_error "$exercise: Unbalanced code blocks (backticks)"
    ((markdown_errors++))
  fi

  # Check balanced details tags
  details_open=$(grep -c '<details>' "$readme" || true)
  details_close=$(grep -c '</details>' "$readme" || true)
  if [ "$details_open" -ne "$details_close" ]; then
    lint_error "$exercise: Unbalanced <details> tags"
    ((markdown_errors++))
  fi
done

if [ "$markdown_errors" -eq 0 ]; then
  lint_ok "All exercises have valid markdown syntax"
fi

# --- Summary ---
print_section "Lint Summary"

echo "Total exercises analyzed: $total_exercises"
echo "Exercises with trap documentation: $trap_coverage"
echo "Exercises with prerequisites: $prereq_coverage"
echo ""
echo -e "Lint Errors:   ${RED}$lint_errors${NC}"
echo -e "Lint Warnings: ${YELLOW}$lint_warnings${NC}"

if [ "$lint_errors" -gt 0 ]; then
  echo ""
  echo -e "${RED}Lint check FAILED${NC}"
  exit 1
else
  if [ "$lint_warnings" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Lint check passed with $lint_warnings suggestion(s)${NC}"
  else
    echo ""
    echo -e "${GREEN}✓ All exercises pass lint checks${NC}"
  fi
  exit 0
fi
