#!/bin/bash
# Question panel for the mock exam (left tmux pane).
# Reads the questions split by mock-exam.sh from .exam-runtime/questions/.
#
# Keys: n/→ next   p/← previous   j/k scroll   g go to question   f flag
#       o overview  s submit (grade)  h help

RUNTIME="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.exam-runtime"
EXAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK_EXAM="$EXAM_DIR/../mock-exam.sh"
STATE="$RUNTIME/state"
INDEX="$RUNTIME/questions/index"
FLAGS="$RUNTIME/flags"

# shellcheck disable=SC1090
source "$STATE"
touch "$FLAGS"

mapfile -t QNUMS < <(cut -d'|' -f1 "$INDEX")
COUNT=${#QNUMS[@]}
CURRENT=0
OFFSET=0
LINES_BUF=()

C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_CODE=$'\e[36m'; C_DIM=$'\e[2m'
C_BAR=$'\e[30;47m'; C_RED=$'\e[1;31m'; C_FLAG=$'\e[1;33m'

field() { awk -F'|' -v q="$1" -v f="$2" '$1 == q { print $f }' "$INDEX"; }
is_flagged() { grep -qx "$1" "$FLAGS"; }

# Markdown → terminal lines, wrapped to the pane width.
render() {
  local file="$1" width="$2" in_code=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == '```'* ]]; then
      in_code=$((1 - in_code)); continue
    fi
    if (( in_code )); then
      printf '%s\n' "  ${C_CODE}${line}${C_RESET}"
      continue
    fi
    if [[ -z "$line" ]]; then echo; continue; fi
    # Wrap first (escape codes would confuse fold), then colour each line.
    sed -E 's/^#+ //' <<<"$line" | fold -s -w "$width" | sed -E \
      -e "s/\*\*([^*]+)\*\*/${C_BOLD}\1${C_RESET}/g" \
      -e "s/\`([^\`]+)\`/${C_CODE}\1${C_RESET}/g" \
      -e 's/[`]|[*][*]//g'
  done <"$file"
}

load_question() {
  local q="${QNUMS[$CURRENT]}" width
  width=$(( $(tput cols) - 2 ))
  (( width < 20 )) && width=20
  mapfile -t LINES_BUF < <(render "$RUNTIME/questions/$q.md" "$width")
  OFFSET=0
}

header() {
  local q="${QNUMS[$CURRENT]}" timer flag="" cols
  cols=$(tput cols)
  timer="$("$EXAM_DIR/timer.sh" "$STATE")"
  is_flagged "$q" && flag=" ⚑ flagged"
  tput cup 0 0
  printf '%s' "$C_BAR"
  printf "%-*s" "$cols" " Q$((10#$q))/$COUNT  ($(field "$q" 2)%)${flag}   ⏱ ${timer}"
  printf '%s' "$C_RESET"
}

draw() {
  local rows body i
  rows=$(tput lines)
  body=$((rows - 3))
  clear
  header
  tput cup 1 0
  for (( i = OFFSET; i < OFFSET + body && i < ${#LINES_BUF[@]}; i++ )); do
    printf '%s\n' "${LINES_BUF[$i]}"
  done
  tput cup $((rows - 1)) 0
  printf '%s' "${C_DIM}n/p next/prev  j/k scroll  g goto  f flag  o overview  s submit  h help${C_RESET}"
}

overview() {
  local q flag
  clear
  echo "${C_BOLD}Questions${C_RESET}"
  echo
  for q in "${QNUMS[@]}"; do
    flag="  "
    is_flagged "$q" && flag="${C_FLAG}⚑${C_RESET} "
    printf " %s%2d  %3s%%  %s\n" "$flag" "$((10#$q))" "$(field "$q" 2)" "$(field "$q" 3)"
  done
  echo
  read -rsn1 -p "${C_DIM}any key to return${C_RESET}"
}

help_screen() {
  clear
  cat <<EOF
${C_BOLD}Mock exam — keys${C_RESET}

  n / →      next question
  p / ←      previous question
  j / k      scroll down / up
  g          go to question number
  f          flag / unflag question
  o          overview of all questions
  s          submit: grade the exam now
  h          this help

Work in the shell pane on the right (Ctrl-b →).
New shell window: Ctrl-b c, switch windows: Ctrl-b n / Ctrl-b p.
Node access: ssh <node-name> (as named in the question).

Exam browser (docs only): ./scripts/mock-exam.sh browser
EOF
  read -rsn1 -p "${C_DIM}any key to return${C_RESET}"
}

submit() {
  local auto="${1:-}"
  clear
  if [[ -z "$auto" ]]; then
    read -rsn1 -p "Submit and grade the exam now? [y/N] " answer
    echo
    [[ "$answer" == [yY] ]] || return
  else
    echo "${C_RED}Time is up — grading.${C_RESET}"
  fi
  "$MOCK_EXAM" grade 2>&1 | tee "$RUNTIME/last-grade.txt"
  echo
  read -rsn1 -p "${C_DIM}any key to return to the questions${C_RESET}"
}

tput civis
trap 'tput cnorm; clear' EXIT
trap 'load_question; draw' WINCH

load_question
draw
while true; do
  key=""
  if ! read -rsn1 -t 1 key; then
    header
    if [[ "$("$EXAM_DIR/timer.sh" "$STATE")" == "TIME UP" && ! -f "$RUNTIME/graded" ]]; then
      touch "$RUNTIME/graded"
      submit auto
      draw
    fi
    continue
  fi
  if [[ "$key" == $'\e' ]]; then
    read -rsn2 -t 0.01 rest
    case "$rest" in
      '[C') key=n ;;
      '[D') key=p ;;
      '[B') key=j ;;
      '[A') key=k ;;
    esac
  fi
  case "$key" in
    n) (( CURRENT < COUNT - 1 )) && { CURRENT=$((CURRENT + 1)); load_question; } ;;
    p) (( CURRENT > 0 )) && { CURRENT=$((CURRENT - 1)); load_question; } ;;
    j) (( OFFSET < ${#LINES_BUF[@]} - 1 )) && OFFSET=$((OFFSET + 3)) ;;
    k) OFFSET=$((OFFSET - 3)); (( OFFSET < 0 )) && OFFSET=0 ;;
    f)
      q="${QNUMS[$CURRENT]}"
      if is_flagged "$q"; then sed -i "/^$q\$/d" "$FLAGS"; else echo "$q" >>"$FLAGS"; fi
      ;;
    g)
      tput cnorm; tput cup "$(( $(tput lines) - 1 ))" 0; tput el
      read -rp "Go to question: " target
      tput civis
      for i in "${!QNUMS[@]}"; do
        [[ "$((10#${QNUMS[$i]}))" == "$target" ]] && { CURRENT=$i; load_question; }
      done
      ;;
    o) overview ;;
    h) help_screen ;;
    s) submit ;;
    *) continue ;;
  esac
  draw
done
