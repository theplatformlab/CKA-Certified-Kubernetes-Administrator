#!/bin/bash
# Docs-only browser for exam sessions: a local allowlist proxy plus a separate
# Firefox profile that uses it.
#
# Usage: scripts/exam/browser.sh start|stop

set -uo pipefail

EXAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Inside the repo (not ~/.local): snap Firefox can't read hidden dirs in $HOME.
RUNTIME="$(cd "$EXAM_DIR/../.." && pwd)/.exam-runtime"
PROXY_PORT="${CKA_PROXY_PORT:-3129}"
# Sites allowed during the real exam (docs, blog, Helm docs, Gateway API docs),
# plus the static asset hosts kubernetes.io needs to render (jQuery, fonts).
ALLOWED_SITES=(kubernetes.io helm.sh gateway-api.sigs.k8s.io
               code.jquery.com fonts.googleapis.com fonts.gstatic.com)

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

start_browser() {
  stop_browser
  mkdir -p "$RUNTIME"
  nohup python3 "$EXAM_DIR/doc-proxy.py" "$PROXY_PORT" "${ALLOWED_SITES[@]}" \
    >"$RUNTIME/proxy.log" 2>&1 &
  echo $! >"$RUNTIME/proxy.pid"

  if ! command -v firefox >/dev/null 2>&1; then
    echo "Firefox not found. Point any browser at proxy 127.0.0.1:${PROXY_PORT} for the docs-only view." >&2
    return 1
  fi
  local profile="$RUNTIME/firefox-profile"
  rm -rf "$profile"; mkdir -p "$profile"
  cat >"$profile/user.js" <<PREFS
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
PREFS
  nohup firefox --new-instance --profile "$profile" "https://kubernetes.io/docs/home/" \
    >"$RUNTIME/firefox.log" 2>&1 &
  echo $! >"$RUNTIME/firefox.pid"
}

case "${1:-}" in
  start) start_browser ;;
  stop) stop_browser ;;
  *) echo "Usage: $0 start|stop" >&2; exit 1 ;;
esac
