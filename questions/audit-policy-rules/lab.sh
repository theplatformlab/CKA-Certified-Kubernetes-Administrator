# shellcheck shell=bash
# Audit log forensics and a fine-grained audit policy. Sourced by scripts/lab.sh.
# Setup enables audit logging with a log-everything-at-Metadata policy, then
# three ServiceAccounts (with their own tokens, so the log shows them as the
# user) read and delete Secrets in payroll. One of them deleted db-backup-key.
# The candidate finds it in the log, then replaces the policy. The API server
# reads the policy only at startup, so it has to be restarted.
LAB_CLUSTER=ops
NS=payroll
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
POLICY=/etc/kubernetes/audit/policy.yaml
LOG=/var/log/kubernetes/audit/audit.log
STATE=/var/lib/cka-lab/audit-policy-rules
BACKUP=/var/lib/cka-lab/backup/_etc_kubernetes_manifests_kube-apiserver.yaml
BOTS="ci-runner report-bot backup-agent"

lab_params() {
  echo "CULPRIT=$(pick ci-runner report-bot backup-agent)"
}

_apiserver_id() { node_exec "$(control_plane_node)" "crictl ps -q --name kube-apiserver --state running | head -1" 2>/dev/null; }

# _wait_restart <old container id> — a new kube-apiserver container is running and ready
_wait_restart() {
  local i id
  for (( i = 0; i < 90; i++ )); do
    id="$(_apiserver_id)"
    [[ -n "$id" && "$id" != "$1" ]] && kc --request-timeout=5s get --raw /readyz >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# _as_bot <bot> <kubectl args...> — kubectl with the bot's own token (no client certificate)
_as_bot() {
  local bot="$1" token server; shift
  token="$(kc -n "$NS" create token "$bot" --duration=10m)"
  server="$(kc config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  kubectl --kubeconfig=/dev/null --server="$server" --insecure-skip-tls-verify --token="$token" "$@"
}

lab_setup() {
  local cp old bot; cp="$(control_plane_node)"
  backup_node_file "$cp" "$MANIFEST"
  old="$(_apiserver_id)"
  node_exec "$cp" "mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit $STATE
    cat > $POLICY <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
EOF
    cp $POLICY $STATE/policy.orig
    rm -f /var/log/kubernetes/audit/*
    cp $BACKUP $STATE/manifest.yaml
    sed -i -e 's|^    - kube-apiserver\$|    - kube-apiserver\n    - --audit-policy-file=$POLICY\n    - --audit-log-path=$LOG\n    - --audit-log-maxsize=100\n    - --audit-log-maxbackup=1|' \
      -e 's|^    volumeMounts:|    volumeMounts:\n    - mountPath: /etc/kubernetes/audit\n      name: audit-policy\n      readOnly: true\n    - mountPath: /var/log/kubernetes/audit\n      name: audit-log|' \
      -e 's|^  volumes:|  volumes:\n  - hostPath:\n      path: /etc/kubernetes/audit\n      type: DirectoryOrCreate\n    name: audit-policy\n  - hostPath:\n      path: /var/log/kubernetes/audit\n      type: DirectoryOrCreate\n    name: audit-log|' $STATE/manifest.yaml
    cp $STATE/manifest.yaml $MANIFEST"
  log_info "Waiting for the kube-apiserver to restart with audit logging (up to 3 minutes) ..."
  if ! _wait_restart "$old"; then
    log_error "kube-apiserver did not come back"
    return 1
  fi
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-janitor
  namespace: $NS
rules:
- apiGroups: [""]
  resources: [secrets, pods]
  verbs: [get, list, delete]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-janitor
  namespace: $NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: secret-janitor
subjects:
$(for bot in $BOTS; do printf -- '- kind: ServiceAccount\n  name: %s\n  namespace: %s\n' "$bot" "$NS"; done)
YAML
  for bot in $BOTS; do kc -n "$NS" create serviceaccount "$bot" --dry-run=client -o yaml | kc apply -f - >/dev/null; done
  for s in db-backup-key report-cache-token payroll-api; do
    kc -n "$NS" create secret generic "$s" --from-literal=value="$(rand_suffix 16)" --dry-run=client -o yaml | kc apply -f - >/dev/null
  done
  # The traffic of the last days: everybody reads, two bots delete something.
  for bot in $BOTS; do
    _as_bot "$bot" -n "$NS" get secrets >/dev/null
    _as_bot "$bot" -n "$NS" get secret db-backup-key >/dev/null
  done
  local other
  for other in $BOTS; do [[ "$other" != "$CULPRIT" ]] && break; done
  _as_bot "$other" -n "$NS" delete secret report-cache-token >/dev/null
  _as_bot "$CULPRIT" -n "$NS" delete secret db-backup-key >/dev/null
  for bot in $BOTS; do _as_bot "$bot" -n "$NS" get pods >/dev/null 2>&1; done
  rm -f "$WORKDIR/deleted-by.txt"
}

# _level <verb> <resource> <namespace> <name> -> audit level of the newest entry for that object
# ("" if none; subresources such as pods/binding don't count)
_level() {
  node_exec "$(control_plane_node)" \
    "grep -F '\"verb\":\"$1\"' $LOG 2>/dev/null | grep -F '\"resource\":\"$2\"' | grep -F '\"namespace\":\"$3\"' \
      | grep -F '\"name\":\"$4\"' | grep -v '\"subresource\"' | tail -1 | grep -o '\"level\":\"[A-Za-z]*\"' | cut -d'\"' -f4" 2>/dev/null
}

lab_check() {
  local cp id; cp="$(control_plane_node)"
  check_gate "The audit policy was changed" node_exec "$cp" "test -s $POLICY && ! cmp -s $POLICY $STATE/policy.orig"
  check_eq "deleted-by.txt names the account that deleted db-backup-key" \
    "$(tr -d '[:space:]' <"$WORKDIR/deleted-by.txt" 2>/dev/null)" "system:serviceaccount:$NS:$CULPRIT"
  check_eq "--audit-policy-file is still $POLICY" \
    "$(node_exec "$cp" "grep -o -- '--audit-policy-file=[^ \"]*' $MANIFEST" 2>/dev/null)" "--audit-policy-file=$POLICY"
  if ! kc --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    _fail "kube-apiserver is up and ready"
    return
  fi
  _pass "kube-apiserver is up and ready"

  id="audit-check-$RANDOM$RANDOM"
  # (No test traffic for an untouched task: the checks fail anyway.)
  [[ -n "$CHECK_GATE" ]] && id="audit-check-skipped"
  [[ -z "$CHECK_GATE" ]] && {
  kc -n "$NS" create secret generic "$id" --from-literal=k=v >/dev/null 2>&1
  kc -n "$NS" get secret "$id" >/dev/null 2>&1
  kc -n "$NS" create configmap "$id" --from-literal=k=v >/dev/null 2>&1
  kc -n "$NS" get configmap "$id" >/dev/null 2>&1
  kc -n "$NS" run "$id" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null 2>&1
  kc -n default run "$id" --image=registry.k8s.io/pause:3.10 --restart=Never >/dev/null 2>&1
  kc -n "$NS" delete secret,configmap "$id" --ignore-not-found >/dev/null 2>&1
  kc -n "$NS" delete pod "$id" --grace-period=0 --force --ignore-not-found >/dev/null 2>&1
  kc -n default delete pod "$id" --grace-period=0 --force --ignore-not-found >/dev/null 2>&1
  sleep 3
  }
  check_eq "Reading a Secret is logged at Metadata" "$(_level get secrets "$NS" "$id")" "Metadata"
  check_eq "Deleting a Secret is logged at Metadata" "$(_level delete secrets "$NS" "$id")" "Metadata"
  check_eq "Creating a Pod in $NS is logged at RequestResponse" "$(_level create pods "$NS" "$id")" "RequestResponse"
  check_eq "Deleting a Pod in $NS is logged at RequestResponse" "$(_level delete pods "$NS" "$id")" "RequestResponse"
  check_eq "Deleting a Pod in default is logged at Metadata" "$(_level delete pods default "$id")" "Metadata"
  check_eq "Reading a ConfigMap is not logged" "$(_level get configmaps "$NS" "$id")" ""
  check_eq "Deleting a ConfigMap is logged at Metadata" "$(_level delete configmaps "$NS" "$id")" "Metadata"
  check_eq "No RequestReceived stage is logged" \
    "$(node_exec "$cp" "grep -F '$id' $LOG | grep -c '\"stage\":\"RequestReceived\"'" 2>/dev/null)" "0"
}

lab_cleanup() {
  local cp old; cp="$(control_plane_node)"
  old="$(_apiserver_id)"
  if node_exec "$cp" "test -f $BACKUP" && ! node_exec "$cp" "cmp -s $BACKUP $MANIFEST"; then
    restore_node_file "$cp" "$MANIFEST"
    log_info "Waiting for the original kube-apiserver to come back ..."
    _wait_restart "$old" || log_warn "kube-apiserver is not ready yet"
  else
    restore_node_file "$cp" "$MANIFEST"
  fi
  node_exec "$cp" "rm -rf /etc/kubernetes/audit /var/log/kubernetes/audit $STATE"
  kc --request-timeout=10s delete namespace "$NS" --ignore-not-found --wait=false
}
