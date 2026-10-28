#!/bin/bash
# Local YAML validation — run before pushing.
# Checks all .yaml files in skeletons/ and exercises/ for syntax errors.
# Requires: Python 3 (for yaml module), optionally yamllint.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
errors=0
checked=0

echo "=== YAML Validation ==="
echo ""

# --- Python YAML syntax check ---
for dir in skeletons exercises; do
  target="$REPO_ROOT/$dir"
  if [ ! -d "$target" ]; then
    continue
  fi

  while IFS= read -r -d '' f; do
    checked=$((checked + 1))
    if python3 -c "import yaml, sys; list(yaml.safe_load_all(open('$f')))" 2>/dev/null; then
      echo -e "  ${GREEN}OK${NC}  $f"
    else
      echo -e "  ${RED}FAIL${NC}  $f"
      errors=$((errors + 1))
    fi
  done < <(find "$target" -name '*.yaml' -print0)
done

echo ""
echo "Checked $checked files, $errors error(s)."

# --- Optional yamllint ---
if command -v yamllint &>/dev/null; then
  echo ""
  echo "=== yamllint ==="
  echo ""
  yamllint -d '{extends: default, rules: {line-length: {max: 200}, truthy: disable, document-start: disable, comments-indentation: disable, indentation: {indent-sequences: whatever}}}' \
    "$REPO_ROOT/skeletons/" && echo -e "${GREEN}yamllint passed${NC}" || echo -e "${YELLOW}yamllint found warnings (see above)${NC}"
else
  echo ""
  echo "Tip: install yamllint (pip install yamllint) for stricter checks."
fi

echo ""
if [ $errors -gt 0 ]; then
  echo -e "${RED}$errors file(s) failed. Fix before pushing.${NC}"
  exit 1
else
  echo -e "${GREEN}All YAML files valid.${NC}"
  exit 0
fi
