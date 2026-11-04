# shellcheck shell=bash
# Inspect the iptables rules of a Service. Sourced by scripts/lab.sh.
# kind runs kube-proxy in iptables mode; every rule kube-proxy writes for a
# Service carries the comment "<namespace>/<service>...".
LAB_CLUSTER=practice
NS=traffic-lab

lab_params() {
  echo "SVC=$(pick quote-api geo-lookup ticket-api)"
  echo "PORT=$(pick 7070 8081 9090 9443)"
}

lab_setup() {
  ensure_ns "$NS"
  rm -f "$WORKDIR/proxy-mode.txt" "$WORKDIR/rules-before.txt" "$WORKDIR/rules-after.txt"
}

# _own <file> — the file has lines, and all of them belong to Service $NS/$SVC
_own() { grep -q . "$1" && ! grep -vE "^\s*$|$NS/${SVC}[\" :]" "$1"; }

_empty() { test -f "$1" && ! grep -q . "$1"; }

lab_check() {
  local before="$WORKDIR/rules-before.txt" after="$WORKDIR/rules-after.txt"
  check_gate "rules-before.txt contains rules" grep -q . "$before"

  # An empty mode in the kube-proxy configuration means the default, iptables.
  local mode; mode="$(jp -n kube-system configmap kube-proxy '{.data.config\.conf}' | sed -n 's/^mode: *"\{0,1\}\([a-z]*\)"\{0,1\}$/\1/p')"
  check_eq "proxy-mode.txt names the proxy mode of kube-proxy" \
    "$(tr -d ' \n' 2>/dev/null <"$WORKDIR/proxy-mode.txt")" "${mode:-iptables}"

  local pod_ip; pod_ip="$(jp -n $NS pod "$SVC" '{.status.podIP}')"
  check_eq "Pod $SVC runs nginx:1.28" \
    "$(jp -n $NS pod "$SVC" '{.spec.containers[0].image} {.status.phase}')" "nginx:1.28 Running"
  check "rules-before.txt has the KUBE-SERVICES rule for port $PORT" \
    grep -qE "^-A KUBE-SERVICES .*$NS/${SVC}[\" :].*--dport $PORT( |$)" "$before"
  check "rules-before.txt has the DNAT rule to $SVC (${pod_ip:-<no pod IP>}:80)" \
    grep -qE "DNAT --to-destination ${pod_ip//./\\.}:80( |$)" "$before"
  check "rules-before.txt contains only rules of Service $SVC" _own "$before"

  check_not "Service $SVC no longer exists" exists -n $NS svc "$SVC"
  check "rules-after.txt exists and is empty" _empty "$after"
  check_eq "$(worker_node) has no rules left for $NS/$SVC" \
    "$(node_exec "$(worker_node)" "iptables-save | grep -cE '$NS/${SVC}[\" :]'" 2>/dev/null)" "0"
}
