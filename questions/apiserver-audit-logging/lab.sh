# shellcheck shell=bash
# API server audit logging. Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
LOG=/var/log/kubernetes/audit/audit.log

lab_setup() {
  backup_node_file "$(control_plane_node)" /etc/kubernetes/manifests/kube-apiserver.yaml
}

_flag() {
  node_exec "$(control_plane_node)" "grep -E -- '- --$1=' /etc/kubernetes/manifests/kube-apiserver.yaml | sed 's/.*--$1=//' | tr -d '\"[:space:]'" 2>/dev/null
}

# _logged <resource> <name> -> prints the audit level of the newest entry for that object, if any
_logged() {
  node_exec "$(control_plane_node)" \
    "grep -F '\"resource\":\"$1\"' $LOG 2>/dev/null | grep -F '\"name\":\"$2\"' | tail -1 | grep -o '\"level\":\"[A-Za-z]*\"' | cut -d'\"' -f4" 2>/dev/null
}

lab_check() {
  local cp; cp="$(control_plane_node)"
  check_gate "Policy file /etc/kubernetes/audit/policy.yaml exists" node_exec "$cp" "test -s /etc/kubernetes/audit/policy.yaml"
  check_eq "--audit-policy-file is set" "$(_flag audit-policy-file)" "/etc/kubernetes/audit/policy.yaml"
  check_eq "--audit-log-path is set" "$(_flag audit-log-path)" "$LOG"
  check_eq "--audit-log-maxage=7" "$(_flag audit-log-maxage)" "7"
  check_eq "--audit-log-maxbackup=3" "$(_flag audit-log-maxbackup)" "3"

  if ! kc --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    _fail "kube-apiserver is up and ready"
    _fail "Secrets are logged at level Metadata"
    _fail "ConfigMaps in default are logged at level Request"
    _fail "Other requests (pods) are not logged"
    return
  fi
  _pass "kube-apiserver is up and ready"

  local id="audit-check-$RANDOM$RANDOM"
  kc -n default create secret generic "$id" --from-literal=k=v >/dev/null 2>&1
  kc -n default create configmap "$id" --from-literal=k=v >/dev/null 2>&1
  # GET requests carry the object name in the audit event's objectRef.
  kc -n default get secret "$id" >/dev/null 2>&1
  kc -n default get configmap "$id" >/dev/null 2>&1
  kc -n default get pod "$id" >/dev/null 2>&1
  sleep 3
  check_eq "Secrets are logged at level Metadata" "$(_logged secrets "$id")" "Metadata"
  check_eq "ConfigMaps in default are logged at level Request" "$(_logged configmaps "$id")" "Request"
  check_eq "Other requests (pods) are not logged" "$(_logged pods "$id")" ""
  kc -n default delete secret,configmap "$id" --ignore-not-found >/dev/null 2>&1
}

lab_cleanup() {
  # Back to the manifest from before the task; the kubelet restarts the API server.
  restore_node_file "$(control_plane_node)" /etc/kubernetes/manifests/kube-apiserver.yaml
  node_exec "$(control_plane_node)" "rm -rf /etc/kubernetes/audit /var/log/kubernetes/audit"
}
