# shellcheck shell=bash
# Restrict access to the API server. Sourced by scripts/lab.sh.
# Setup makes the API server insecure: an explicit --anonymous-auth=true with a
# ClusterRoleBinding that lets anonymous users read the cluster, a static token
# file with a system:masters token, and no NodeRestriction admission plugin.
# The trap: --anonymous-auth=false also rejects kubeadm's unauthenticated
# liveness/readiness/startup probes, and the API server never gets Ready.
# Since v1.32 an AuthenticationConfiguration (--authentication-config) can
# keep anonymous access for the health endpoints only.
# (AlwaysAllow can't be the insecure setting here: the API server turns
# anonymous auth off when AlwaysAllow is in --authorization-mode, so the
# probes would fail right after setup.)
LAB_CLUSTER=ops
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
STATE=/var/lib/cka-lab/apiserver-access-hardening
BACKUP=/var/lib/cka-lab/backup/_etc_kubernetes_manifests_kube-apiserver.yaml
TOKEN_FILE=/etc/kubernetes/pki/static-tokens.csv
CRB=anonymous-readonly

lab_params() {
  echo "STATIC_TOKEN=$(rand_suffix 24)"
}

# _wait_api <test command...> — up to ~3 minutes until the command succeeds
_wait_api() {
  local i
  for (( i = 0; i < 90; i++ )); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  return 1
}
_apiserver_id() { node_exec "$(control_plane_node)" "crictl ps -q --name kube-apiserver --state running | head -1" 2>/dev/null; }
_new_apiserver() { local id; id="$(_apiserver_id)"; [[ -n "$id" && "$id" != "$1" ]]; }

lab_setup() {
  local cp old; cp="$(control_plane_node)"
  backup_node_file "$cp" "$MANIFEST"
  old="$(_apiserver_id)"
  # Always start from the pristine manifest, so a repeated setup gives the same state.
  node_exec "$cp" "mkdir -p $STATE && cp $BACKUP $STATE/insecure.yaml
    echo '$STATIC_TOKEN,legacy-admin,9001,system:masters' > $TOKEN_FILE
    sed -i -e '/^    - --enable-admission-plugins=/d' \
      -e 's|^    - --allow-privileged=true|    - --allow-privileged=true\n    - --anonymous-auth=true|' \
      -e 's|^    - --tls-private-key-file=\(.*\)|    - --tls-private-key-file=\1\n    - --token-auth-file=$TOKEN_FILE|' $STATE/insecure.yaml
    cmp -s $STATE/insecure.yaml $MANIFEST || { cp $STATE/insecure.yaml $MANIFEST; echo changed > $STATE/changed; }"
  if node_exec "$cp" "test -f $STATE/changed && rm -f $STATE/changed"; then
    log_info "Waiting for the kube-apiserver to restart with the new settings (up to 3 minutes) ..."
    _wait_api _new_apiserver "$old" || true
  fi
  if ! _wait_api kc --request-timeout=5s get --raw /readyz; then
    log_error "kube-apiserver did not come back"
    return 1
  fi
  kc apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $CRB
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:anonymous
YAML
}

# _flag <name> -> value of --<name> in the manifest
_flag() {
  node_exec "$(control_plane_node)" "grep -E -- '^ *- --$1=' $MANIFEST | tail -1 | sed 's/.*--$1=//' | tr -d '\"[:space:]'" 2>/dev/null
}

# _anon <path> [curl args] -> HTTP status of a request without client certificate from the control plane node
_anon() {
  node_exec "$(control_plane_node)" "curl -sk -m 5 -o /dev/null -w '%{http_code}' ${2:-} https://127.0.0.1:6443$1" 2>/dev/null
}

# _node_restriction_denies — a kubelet may not set node-restriction.kubernetes.io/ labels on its own Node
# (only the NodeRestriction admission plugin rejects that; server-side dry run, nothing is changed)
_node_restriction_denies() {
  local w; w="$(worker_node)"
  kc --request-timeout=10s --as "system:node:$w" --as-group system:nodes \
    label node "$w" node-restriction.kubernetes.io/cks-check=true --dry-run=server 2>&1 | grep -q 'not allowed to modify labels'
}

lab_check() {
  local cp; cp="$(control_plane_node)"
  check_gate "kube-apiserver manifest was changed" \
    node_exec "$cp" "test -f $STATE/insecure.yaml && ! cmp -s $STATE/insecure.yaml $MANIFEST"
  check_eq "API server answers /readyz" "$(kc --request-timeout=10s get --raw /readyz 2>/dev/null)" "ok"
  check_eq "kube-apiserver pod is Ready" \
    "$(kc --request-timeout=10s -n kube-system get pod "kube-apiserver-$cp" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" "True"
  check_eq "Anonymous request to /api/v1/namespaces is rejected with 401" "$(_anon /api/v1/namespaces)" "401"
  check_eq "Anonymous request to /version is rejected with 401" "$(_anon /version)" "401"
  check_eq "Anonymous health checks still work (/livez /readyz /healthz)" \
    "$(_anon /livez) $(_anon /readyz) $(_anon /healthz)" "200 200 200"
  check_eq "The static token of legacy-admin is rejected (401)" \
    "$(_anon /api/v1/namespaces "-H 'Authorization: Bearer $STATIC_TOKEN'")" "401"
  check_eq "--token-auth-file is no longer set" "$(_flag token-auth-file)" ""
  check_not "Static token file $TOKEN_FILE is deleted" node_exec "$cp" "test -e $TOKEN_FILE"
  check_not "ClusterRoleBinding $CRB is deleted" kc --request-timeout=10s get clusterrolebinding "$CRB"
  check_match "--enable-admission-plugins includes NodeRestriction" "$(_flag enable-admission-plugins)" '(^|,)NodeRestriction(,|$)'
  check "NodeRestriction stops a kubelet from setting node-restriction.kubernetes.io labels" _node_restriction_denies
}

lab_cleanup() {
  local cp i; cp="$(control_plane_node)"
  if node_exec "$cp" "test -f $BACKUP"; then
    restore_node_file "$cp" "$MANIFEST"
    log_info "Waiting for the original kube-apiserver to come back ..."
    # Back to kubeadm's defaults: anonymous requests are authenticated again (no more 401).
    for (( i = 0; i < 90; i++ )); do [[ "$(_anon /version)" == 200 ]] && break; sleep 2; done
    _wait_api kc --request-timeout=5s get --raw /readyz || true
  fi
  kc --request-timeout=10s delete clusterrolebinding "$CRB" --ignore-not-found >/dev/null 2>&1
  node_exec "$cp" "rm -rf $STATE $TOKEN_FILE /etc/kubernetes/auth"
}
