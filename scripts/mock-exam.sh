#!/bin/bash
# Mock exam simulator — exam-like environment with automatic grading.
#
# Usage:
#   ./scripts/mock-exam.sh start <N> [options]   Prepare clusters + questions and open the exam
#       --minutes M     exam duration (default 120)
#       --reuse         keep existing exam clusters instead of recreating them
#       --here          attach the exam session in this terminal instead of a new window
#       --no-browser    don't start the docs-only browser
#   ./scripts/mock-exam.sh attach                 Re-open the exam session (tmux)
#   ./scripts/mock-exam.sh browser                (Re)start the docs-only browser
#   ./scripts/mock-exam.sh grade                  Grade the running exam (also: 's' in the question panel)
#   ./scripts/mock-exam.sh stop [--keep-clusters] End the exam and delete the exam clusters
#   ./scripts/mock-exam.sh question <N> <Q> setup|check
#                                                 Run one question's setup or check (practice/debugging)
#
# The exam runs on its own kind clusters (cka-exam, cka-exam-ops), so your
# practice clusters are not touched. Questions live in mock-exams/MOCK-EXAM-NN.md,
# their setup/check scripts in mock-exams/exam-NN/qNN.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

export CKA_PRACTICE_CLUSTER="cka-exam"
export CKA_OPS_CLUSTER="cka-exam-ops"
export CKA_EXAM_HOME="$HOME/cka-exam"
# Own docker network for the exam nodes, so they don't compete for addresses
# with the practice clusters on the default "kind" network.
export KIND_EXPERIMENTAL_DOCKER_NETWORK="kind-exam"

RUNTIME="$REPO_ROOT/.exam-runtime"
STATE="$RUNTIME/state"
SESSION="cka-exam"
PROXY_PORT=3129
# Sites allowed during the real exam (docs, blog, Helm docs, Gateway API docs),
# plus the static asset hosts kubernetes.io needs to render (jQuery, fonts).
ALLOWED_SITES=(kubernetes.io helm.sh gateway-api.sigs.k8s.io
               code.jquery.com fonts.googleapis.com fonts.gstatic.com)

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }

exam_dir() { echo "$REPO_ROOT/mock-exams/exam-$(printf "%02d" "$((10#$1))")"; }
exam_file() { echo "$REPO_ROOT/mock-exams/MOCK-EXAM-$(printf "%02d" "$((10#$1))").md"; }

# Split MOCK-EXAM-NN.md into one file per question plus an index
# ("NN|weight|title"). Question headers look like: ## Question 3 — Title (7%)
split_questions() {
  local file="$1" out="$RUNTIME/questions"
  rm -rf "$out"; mkdir -p "$out"
  awk -v out="$out" '
    /^## Question [0-9]+/ {
      match($0, /Question [0-9]+/); num = sprintf("%02d", substr($0, RSTART + 9, RLENGTH - 9))
      weight = ""; if (match($0, /\([0-9]+%\)/)) weight = substr($0, RSTART + 1, RLENGTH - 3)
      title = $0; sub(/^## Question [0-9]+ *[—:-]* */, "", title); sub(/ *\([0-9]+%\) *$/, "", title)
      current = out "/" num ".md"
      print num "|" weight "|" title >> (out "/index")
      print > current
      next
    }
    /^## End/ { current = "" }
    /^---$/ { next }
    current != "" { print >> current }
  ' "$file"
}

question_cluster() { sed -n 's/^Q_CLUSTER=\([a-z]*\).*/\1/p' "$1"; }

# Run one function (q_setup / q_check) of a question script in a subshell.
run_question() {
  local qfile="$1" fn="$2"
  (
    set +u
    # shellcheck source=lib/check.sh
    source "$SCRIPT_DIR/lib/check.sh"
    Q_CLUSTER=practice
    # shellcheck disable=SC1090
    source "$qfile"
    use_cluster "$(cluster_name "$Q_CLUSTER")"
    if [[ "$fn" == q_check ]]; then
      set +eo pipefail
      check_reset
      q_check
      echo "__RESULT__ $CHECK_PASS $CHECK_FAIL"
    elif declare -F "$fn" >/dev/null; then
      set -euo pipefail
      "$fn"
    fi
  )
}

create_clusters() {
  local dir="$1" profiles=() p pids=() failed=0
  for p in practice ops; do
    if grep -lq "^Q_CLUSTER=$p" "$dir"/q*.sh; then profiles+=("$p"); fi
  done
  for p in "${profiles[@]}"; do
    local name; name="$(cluster_name "$p")"
    if [[ "$REUSE" == true ]] && cluster_exists "$name"; then
      log_info "Reusing cluster $name"
      continue
    fi
    log_info "Creating cluster $name (profile $p) — log: $RUNTIME/cluster-$p.log"
    CLUSTER_NAME="$name" "$SCRIPT_DIR/init-cluster.sh" --profile "$p" --recreate >"$RUNTIME/cluster-$p.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || failed=1; done
  if (( failed )); then
    log_error "Cluster creation failed, see $RUNTIME/cluster-*.log"
    exit 1
  fi
}

setup_questions() {
  local dir="$1" qfile q pids=() names=() i failed=0
  # Practice-cluster questions are independent: set them up in parallel.
  for qfile in "$dir"/q*.sh; do
    [[ "$(question_cluster "$qfile")" == ops ]] && continue
    q="$(basename "$qfile" .sh)"
    run_question "$qfile" q_setup >"$RUNTIME/setup-$q.log" 2>&1 &
    pids+=($!); names+=("$q")
  done
  # Ops-cluster questions may break the control plane: run them in order.
  for qfile in "$dir"/q*.sh; do
    [[ "$(question_cluster "$qfile")" == ops ]] || continue
    q="$(basename "$qfile" .sh)"
    if ! run_question "$qfile" q_setup >"$RUNTIME/setup-$q.log" 2>&1; then
      log_error "Setup of $q failed, see $RUNTIME/setup-$q.log"; failed=1
    fi
  done
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      log_error "Setup of ${names[$i]} failed, see $RUNTIME/setup-${names[$i]}.log"; failed=1
    fi
  done
  return "$failed"
}

start_browser() {
  stop_browser
  mkdir -p "$RUNTIME"
  nohup python3 "$SCRIPT_DIR/exam/doc-proxy.py" "$PROXY_PORT" "${ALLOWED_SITES[@]}" \
    >"$RUNTIME/proxy.log" 2>&1 &
  echo $! >"$RUNTIME/proxy.pid"

  if ! command -v firefox >/dev/null 2>&1; then
    log_warn "Firefox not found. Point any browser at proxy 127.0.0.1:${PROXY_PORT} to get the docs-only view."
    return
  fi
  local profile="$RUNTIME/firefox-profile"
  rm -rf "$profile"; mkdir -p "$profile"
  cat >"$profile/user.js" <<EOF
user_pref("network.proxy.type", 1);
user_pref("network.proxy.http", "127.0.0.1");
user_pref("network.proxy.http_port", ${PROXY_PORT});
user_pref("network.proxy.ssl", "127.0.0.1");
user_pref("network.proxy.ssl_port", ${PROXY_PORT});
user_pref("network.proxy.share_proxy_settings", true);
user_pref("network.proxy.no_proxies_on", "");
user_pref("network.proxy.allow_hijacking_localhost", true);
user_pref("network.trr.mode", 5);
user_pref("browser.startup.homepage", "https://kubernetes.io/docs/home/");
user_pref("browser.startup.page", 1);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("app.update.auto", false);
user_pref("extensions.pocket.enabled", false);
user_pref("signon.rememberSignons", false);
EOF
  nohup firefox --new-instance --profile "$profile" "https://kubernetes.io/docs/home/" \
    >"$RUNTIME/firefox.log" 2>&1 &
  echo $! >"$RUNTIME/firefox.pid"
  log_info "Docs browser started (allowed: ${ALLOWED_SITES[*]:0:3})"
}

stop_browser() {
  local f
  for f in firefox proxy; do
    if [[ -f "$RUNTIME/$f.pid" ]]; then
      kill "$(cat "$RUNTIME/$f.pid")" 2>/dev/null || true
      rm -f "$RUNTIME/$f.pid"
    fi
  done
  # Snap Firefox re-execs, so the pid above may be a wrapper: match the profile too.
  pkill -f -- "--profile $RUNTIME/firefox-profile" 2>/dev/null || true
}

start_session() {
  local exam_num="$1" here="$2"
  local rc="$SCRIPT_DIR/exam/bashrc"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -n exam -x 220 -y 50 \
    -e CKA_EXAM_HOME="$CKA_EXAM_HOME" -c "$CKA_EXAM_HOME" "bash --rcfile '$rc'"
  tmux set -t "$SESSION" default-command "bash --rcfile '$rc'"
  tmux set -t "$SESSION" mouse on
  tmux set -t "$SESSION" status-interval 1
  tmux set -t "$SESSION" status-style "bg=colour24,fg=white"
  tmux set -t "$SESSION" status-left " CKA Mock Exam $(printf "%02d" "$exam_num") │ "
  tmux set -t "$SESSION" status-left-length 30
  tmux set -t "$SESSION" status-right " ⏱ #($SCRIPT_DIR/exam/timer.sh) "
  tmux split-window -t "$SESSION:exam" -h -b -l 45% "bash '$SCRIPT_DIR/exam/viewer.sh'"
  tmux select-pane -t "$SESSION:exam.1"

  if [[ "$here" != true ]] && command -v wt.exe >/dev/null 2>&1 && [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    wt.exe -w new wsl.exe -d "$WSL_DISTRO_NAME" -- tmux attach -t "$SESSION" >/dev/null 2>&1 &
    log_info "Exam opened in a new Windows Terminal window (re-open: ./scripts/mock-exam.sh attach)"
  elif [[ -t 0 && -z "${TMUX:-}" ]]; then
    exec tmux attach -t "$SESSION"
  else
    log_info "Attach to the exam with: tmux attach -t $SESSION"
  fi
}

cmd_start() {
  local exam_num="${1:-}"; shift || true
  local minutes=120 here=false browser=true
  REUSE=false
  [[ -n "$exam_num" ]] || { log_error "Missing exam number"; usage; exit 1; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --minutes) minutes="$2"; shift ;;
      --reuse) REUSE=true ;;
      --here) here=true ;;
      --no-browser) browser=false ;;
      *) log_error "Unknown option: $1"; exit 1 ;;
    esac
    shift
  done

  local dir file
  dir="$(exam_dir "$exam_num")"; file="$(exam_file "$exam_num")"
  [[ -f "$file" && -d "$dir" ]] || { log_error "Mock exam $exam_num not found"; exit 1; }
  for cmd in docker kind kubectl tmux python3; do
    command -v "$cmd" >/dev/null 2>&1 || { log_error "'$cmd' is required"; exit 1; }
  done
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    log_error "An exam is already running. Attach with './scripts/mock-exam.sh attach' or end it with './scripts/mock-exam.sh stop'."
    exit 1
  fi

  rm -rf "$RUNTIME"; mkdir -p "$RUNTIME"
  rm -rf "$CKA_EXAM_HOME"; mkdir -p "$CKA_EXAM_HOME"

  create_clusters "$dir"
  log_info "Preparing questions ..."
  if ! setup_questions "$dir"; then
    log_error "Some questions could not be prepared; the exam would not be fair. Fix and retry (--reuse skips cluster creation)."
    exit 1
  fi
  split_questions "$file"
  kubectl config use-context "kind-${CKA_PRACTICE_CLUSTER}" >/dev/null

  local now; now="$(date +%s)"
  cat >"$STATE" <<EOF
EXAM_NUM=$exam_num
START_TS=$now
END_TS=$((now + minutes * 60))
EOF
  [[ "$browser" == true ]] && start_browser
  log_info "Exam started: $(wc -l <"$RUNTIME/questions/index") questions, ${minutes} minutes. Good luck!"
  start_session "$exam_num" "$here"
}

cmd_grade() {
  [[ -f "$STATE" ]] || { log_error "No exam running"; exit 1; }
  # shellcheck disable=SC1090
  source "$STATE"
  local dir qfile q weight title out pass fail score total_score=0 max_score=0
  dir="$(exam_dir "$EXAM_NUM")"
  local report="$RUNTIME/result-$(date +%Y%m%d-%H%M%S).txt"
  {
    echo -e "${BOLD}Mock Exam $(printf "%02d" "$EXAM_NUM") — results${NC}"
    echo ""
    while IFS='|' read -r q weight title; do
      qfile="$dir/q$q.sh"
      echo -e "${BLUE}${BOLD}Question $((10#$q)) — $title (${weight}%)${NC}"
      out="$(run_question "$qfile" q_check 2>&1)"
      grep -v '^__RESULT__' <<<"$out"
      read -r pass fail < <(sed -n 's/^__RESULT__ //p' <<<"$out")
      pass="${pass:-0}"; fail="${fail:-0}"
      (( pass + fail == 0 )) && fail=1
      # Partial credit: weight * passed checks / all checks (in tenths of a percent).
      score=$(( weight * 10 * pass / (pass + fail) ))
      total_score=$((total_score + score)); max_score=$((max_score + weight * 10))
      echo -e "  → $((score / 10)).$((score % 10)) / ${weight}"
      echo ""
    done <"$RUNTIME/questions/index"
    local pct=$(( total_score * 100 / max_score ))
    if (( pct >= 66 )); then
      echo -e "${GREEN}${BOLD}Score: ${pct}% — PASS${NC} (66% needed)"
    else
      echo -e "${RED}${BOLD}Score: ${pct}% — FAIL${NC} (66% needed)"
    fi
    echo "Solutions: mock-exams/MOCK-EXAM-$(printf "%02d" "$EXAM_NUM")-SOLUTIONS.md"
  } | tee "$report"
}

cmd_stop() {
  local keep=false
  [[ "${1:-}" == "--keep-clusters" ]] && keep=true
  stop_browser
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  if [[ "$keep" == false ]]; then
    local p
    for p in practice ops; do
      cluster_exists "$(cluster_name "$p")" && kind delete cluster --name "$(cluster_name "$p")"
    done
  fi
  rm -f "$STATE"
  log_info "Exam ended. Results are kept in $RUNTIME/result-*.txt until the next start."
}

cmd_question() {
  local exam_num="${1:-}" q="${2:-}" action="${3:-}" qfile
  [[ -n "$exam_num" && -n "$q" && "$action" =~ ^(setup|check)$ ]] || { usage; exit 1; }
  qfile="$(exam_dir "$exam_num")/q$(printf "%02d" "$((10#$q))").sh"
  [[ -f "$qfile" ]] || { log_error "Question not found: $qfile"; exit 1; }
  mkdir -p "$CKA_EXAM_HOME"
  if [[ "$action" == setup ]]; then
    run_question "$qfile" q_setup
  else
    run_question "$qfile" q_check | grep -v '^__RESULT__'
  fi
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    start) cmd_start "$@" ;;
    attach) exec tmux attach -t "$SESSION" ;;
    browser) start_browser ;;
    grade|submit) cmd_grade ;;
    stop) cmd_stop "$@" ;;
    question) cmd_question "$@" ;;
    -h|--help|"") usage ;;
    *) log_error "Unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
