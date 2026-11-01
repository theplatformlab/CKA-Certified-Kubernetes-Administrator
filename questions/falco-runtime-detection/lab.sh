# shellcheck shell=bash
# Falco runs as systemd service on the worker (init-cluster.sh --profile cks).
# One of three Deployments reads /etc/shadow every few seconds; find it in the
# Falco alerts, stop it and add a custom rule. Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
NS=shop-backend
LOCAL_RULES=/etc/falco/falco_rules.local.yaml

lab_params() {
  echo "BAD=$(pick cart checkout catalog)"
}

# The loops are base64-encoded so the Deployments look alike; only the
# Falco alerts tell which one reads /etc/shadow.
_deployment() {
  local name="$1" loop
  if [[ "$name" == "$BAD" ]]; then
    loop='while true; do cat /etc/shadow > /dev/null; echo "sync $(date +%s)" > /tmp/state; sleep 5; done'
  else
    loop='while true; do echo "sync $(date +%s)" > /tmp/state; sleep 5; done'
  fi
  cat <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels: {app: $name}
  template:
    metadata:
      labels: {app: $name}
    spec:
      containers:
      - name: app
        image: busybox:1.37
        command: ["sh", "-c", "echo $(printf '%s' "$loop" | base64 -w0) | base64 -d | sh"]
YAML
}

lab_setup() {
  local w; w="$(worker_node 1)"
  if ! node_exec "$w" "systemctl is-active -q falco" 2>/dev/null; then
    log_error "Falco is not running on $w. Create the cluster with: ./scripts/init-cluster.sh --profile cks"
    return 1
  fi
  backup_node_file "$w" "$LOCAL_RULES"
  rm -f "$WORKDIR/falco-incident.txt"
  ensure_ns "$NS"
  local d
  for d in cart checkout catalog; do _deployment "$d" | kc apply -f - >/dev/null; done
  kc -n "$NS" rollout status deploy/cart deploy/checkout deploy/catalog --timeout=120s >/dev/null
}

# _custom_rule_fires -> runs a shell in a Pod of a healthy Deployment and looks
# for the required output line in the Falco log. (exec only runs 'echo'.)
_custom_rule_fires() {
  local d pod token
  # Not graded anyway after a failed gate: don't exec into Pods for nothing.
  [[ -z "$CHECK_GATE" ]] || return 1
  for d in cart checkout catalog; do [[ "$d" != "$BAD" ]] && break; done
  pod="$(kc -n "$NS" get pod -l app="$d" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [[ -n "$pod" ]] || return 1
  token="cka-$RANDOM$RANDOM"
  kc -n "$NS" exec "$pod" -- sh -c "echo $token" >/dev/null 2>&1 || return 1
  local i
  for i in 1 2 3 4 5 6; do
    sleep 1
    node_exec "$(worker_node 1)" "journalctl -u falco --no-pager --since '-2min' | grep -F 'Shell in container' | grep -F 'pod=$pod ' | grep -F 'ns=$NS ' | grep -qF '$token'" && return 0
  done
  return 1
}

lab_check() {
  local w answer; w="$(worker_node 1)"
  answer="$(cat "$WORKDIR/falco-incident.txt" 2>/dev/null | tr -d "[:space:]")"
  check_gate "falco-incident.txt exists" test -n "$answer"
  # check, not check_match: a failed check must not print the answer
  check "falco-incident.txt names the Pod that reads /etc/shadow" grep -qE "^${BAD}-[a-z0-9]+-[a-z0-9]+$" <<<"$answer"
  check_eq "The Deployment of that Pod is scaled to 0" "$(jp -n "$NS" deploy "$BAD" '{.spec.replicas}')" "0"
  local d
  for d in cart checkout catalog; do
    [[ "$d" == "$BAD" ]] && continue
    check_eq "Deployment $d (not involved) still runs 1 Pod" "$(jp -n "$NS" deploy "$d" '{.status.readyReplicas}')" "1"
  done
  check_eq "falco service is active on $w" "$(node_exec "$w" "systemctl is-active falco" 2>/dev/null)" "active"
  check "Custom rule logs shells in containers as 'Shell in container: user=... pod=... ns=... cmd=...'" _custom_rule_fires
}

lab_cleanup() {
  local w; w="$(worker_node 1)"
  restore_node_file "$w" "$LOCAL_RULES"
  node_exec "$w" "rm -f /etc/falco/rules.d/*; systemctl restart falco" >/dev/null 2>&1 || true
  rm -f "$WORKDIR/falco-incident.txt"
}
