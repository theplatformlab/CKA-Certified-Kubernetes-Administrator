#!/bin/bash
# Validate Exercise Structure and Quality
# Ensures all exercises follow consistent patterns and have required content.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXERCISES_DIR="$REPO_ROOT/exercises"

errors=0
warnings=0
checked=0

# Colors for output
print_header() {
  echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_ok() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
  ((errors++))
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((warnings++))
}

# --- Check exercise structure ---
print_header "Exercise Structure Validation"

for exercise_dir in "$EXERCISES_DIR"/[0-9]*-*/; do
  if [ ! -d "$exercise_dir" ]; then
    continue
  fi

  exercise_name=$(basename "$exercise_dir")
  ((checked++))

  # Check README.md exists
  if [ ! -f "$exercise_dir/README.md" ]; then
    print_error "$exercise_name: Missing README.md"
    continue
  fi

  readme="$exercise_dir/README.md"
  
  # Check required README sections
  if ! grep -q "^# Exercise" "$readme"; then
    print_warning "$exercise_name: Missing '# Exercise' title"
  fi

  if ! grep -q "## Tasks" "$readme" && ! grep -q "## Objectives" "$readme"; then
    print_warning "$exercise_name: Missing '## Tasks' or '## Objectives' section"
  fi

  if ! grep -q "## Hints" "$readme" && ! grep -q "<details>" "$readme"; then
    print_warning "$exercise_name: Missing hints or details section"
  fi

  if ! grep -q "## Verify" "$readme"; then
    print_warning "$exercise_name: Missing '## Verify' section"
  fi

  # Check for related resources section
  if ! grep -q "Related:" "$readme" && ! grep -q "Related |" "$readme"; then
    print_warning "$exercise_name: Consider adding 'Related' section with skeleton references"
  fi

  # Check for reasonable content length (at least 50 lines)
  line_count=$(wc -l < "$readme")
  if [ "$line_count" -lt 50 ]; then
    print_warning "$exercise_name: Exercise may be incomplete ($line_count lines)"
  fi

  print_ok "$exercise_name ($line_count lines)"
done

# --- Check YAML skeleton files ---
print_header "YAML Skeleton Validation"

skeleton_errors=0
for yaml_file in "$REPO_ROOT/skeletons"/*.yaml; do
  if [ ! -f "$yaml_file" ]; then
    continue
  fi

  filename=$(basename "$yaml_file")
  if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
    print_error "Skeleton: $filename has syntax errors"
    ((skeleton_errors++))
  else
    print_ok "Skeleton: $filename"
  fi
done

# --- Check for unused skeletons ---
print_header "Unused Skeleton Detection"

unused=0
for yaml_file in "$REPO_ROOT/skeletons"/*.yaml; do
  if [ ! -f "$yaml_file" ]; then
    continue
  fi

  filename=$(basename "$yaml_file")
  skeleton_name="${filename%.yaml}"
  
  # Search for references in exercise README files
  if ! grep -r "$skeleton_name" "$EXERCISES_DIR" >/dev/null 2>&1; then
    print_warning "Skeleton '$filename' not referenced in any exercise"
    ((unused++))
  fi
done

if [ "$unused" -eq 0 ]; then
  print_ok "All skeletons are referenced"
fi

# --- Summary ---
print_header "Summary"

echo "Exercises checked: $checked"
echo "YAML files validated: $(ls -1 "$REPO_ROOT/skeletons"/*.yaml 2>/dev/null | wc -l)"
echo ""
echo -e "Errors:   ${RED}$errors${NC}"
echo -e "Warnings: ${YELLOW}$warnings${NC}"

if [ "$errors" -gt 0 ]; then
  echo ""
  echo -e "${RED}Validation FAILED${NC}"
  exit 1
else
  if [ "$warnings" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Validation passed with $warnings warning(s)${NC}"
  else
    echo ""
    echo -e "${GREEN}✓ All exercises validated successfully${NC}"
  fi
  exit 0
fi
