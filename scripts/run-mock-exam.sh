#!/bin/bash
# run-mock-exam.sh — Timed mock exam runner with exam simulation
# Provides exam-like experience: read questions, solve in time, self-score
#
# Usage: bash scripts/run-mock-exam.sh [exam-num] [time-minutes]
# Ex:    bash scripts/run-mock-exam.sh 1           (Mock Exam 01, 120 min)
#        bash scripts/run-mock-exam.sh 2 90        (Mock Exam 02, 90 min)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MOCK_EXAMS_DIR="$REPO_ROOT/mock-exams"

# Defaults
EXAM_NUM="${1:-1}"
TIME_MINUTES="${2:-120}"
TIME_SECONDS=$((TIME_MINUTES * 60))

# Exam files
EXAM_FILE="$MOCK_EXAMS_DIR/MOCK-EXAM-$(printf "%02d" "$EXAM_NUM").md"
SOLUTION_FILE="$MOCK_EXAMS_DIR/MOCK-EXAM-$(printf "%02d" "$EXAM_NUM")-SOLUTIONS.md"

# Validate exam exists
if [[ ! -f "$EXAM_FILE" ]]; then
  echo -e "${RED}✗${NC} Mock Exam $(printf "%02d" "$EXAM_NUM") not found at $EXAM_FILE"
  exit 1
fi

# ANSI timer
show_timer() {
  local remaining=$1
  local minutes=$((remaining / 60))
  local seconds=$((remaining % 60))
  
  if (( remaining < 300 )); then
    # Last 5 minutes: red
    echo -ne "\r${RED}⏱ TIME: ${minutes}:$(printf "%02d" $seconds) — HURRY!${NC}        "
  elif (( remaining < 1200 )); then
    # 5-20 minutes: yellow
    echo -ne "\r${YELLOW}⏱ TIME: ${minutes}:$(printf "%02d" $seconds)${NC}        "
  else
    # Plenty of time: green
    echo -ne "\r${GREEN}⏱ TIME: ${minutes}:$(printf "%02d" $seconds)${NC}        "
  fi
}

# Main exam flow
main() {
  clear
  
  # Header
  echo -e "${BLUE}"
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║          CKA MOCK EXAM $(printf "%02d" "$EXAM_NUM") — SIMULATED CONDITIONS         ║"
  echo "║                    $TIME_MINUTES Minutes            ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  
  echo "📋 Exam Rules:"
  echo "  • Answer in /tmp/cka-exam-answers (create one file per question)"
  echo "  • Use kubectl and bash to solve tasks"
  echo "  • You may reference: kubernetes.io/docs, kubernetes.io/blog, github.com/kubernetes"
  echo "  • No copy-pasting from solutions"
  echo "  • Time limit: $TIME_MINUTES minutes"
  echo ""
  
  # Show exam questions
  echo -e "${BLUE}=== EXAM QUESTIONS ===${NC}"
  echo ""
  head -100 "$EXAM_FILE" | tail -n +2  # Skip title, show first 100 lines
  echo ""
  
  # Confirmation
  echo -n "Press ENTER to start timer (or Ctrl+C to quit)..."
  read -r
  
  clear
  
  # Start timer countdown
  local start_time=$(date +%s)
  local end_time=$((start_time + TIME_SECONDS))
  
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║ EXAM IN PROGRESS — Solve questions in /tmp/cka-exam-answers ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "📝 Questions are above. Solve them using kubectl."
  echo "💾 Create answer files in /tmp/cka-exam-answers/"
  echo ""
  
  # Timer loop
  while true; do
    local now=$(date +%s)
    local remaining=$((end_time - now))
    
    if (( remaining <= 0 )); then
      echo -e "\r${RED}⏱ TIME'S UP! — SESSION ENDED${NC}                              "
      break
    fi
    
    show_timer "$remaining"
    sleep 1
  done
  
  # Post-exam flow
  echo ""
  echo ""
  echo -e "${GREEN}✓ Exam session ended.${NC}"
  echo ""
  echo "📊 Next Steps:"
  echo "  1. Review your answers in /tmp/cka-exam-answers/"
  echo "  2. Check SOLUTIONS: less $SOLUTION_FILE"
  echo "  3. Self-score using GRADING.md scale (9-10 = mastered)"
  echo "  4. Identify weak domains for final prep"
  echo ""
  
  # Ask if ready to see solutions
  echo -n "Ready to review solutions? (y/n): "
  read -r response
  
  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}=== SOLUTIONS & EXPLANATIONS ===${NC}"
    less "$SOLUTION_FILE"
  fi
  
  echo ""
  echo -e "${GREEN}✓ Mock Exam complete. Ready for real CKA? Use GRADING.md to self-assess.${NC}"
}

# Show usage
usage() {
  cat <<EOF
Usage: bash scripts/run-mock-exam.sh [exam-num] [time-minutes]

Examples:
  bash scripts/run-mock-exam.sh           # Mock Exam 01, 120 minutes
  bash scripts/run-mock-exam.sh 2         # Mock Exam 02, 120 minutes
  bash scripts/run-mock-exam.sh 1 90      # Mock Exam 01, 90 minutes

Available Exams:
  01 — Mock Exam 01 (15 questions)
  02 — Mock Exam 02 (15 questions)

Time Recommendations:
  120 minutes — Full exam simulation (real CKA time)
  90 minutes  — Quick practice
  60 minutes  — Speed test

After exam:
  • Review answers in /tmp/cka-exam-answers/
  • Check SOLUTIONS file for explanations
  • Score yourself using GRADING.md rubric
  • Use DOMAINS.md to identify weak areas
EOF
}

# Main
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  usage
  exit 0
fi

main
