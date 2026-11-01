# shellcheck shell=bash
# Encrypt Secrets at rest. Sourced by scripts/lab.sh.
# The check reads etcd directly: every key under /registry/secrets must carry
# the k8s:enc:<provider>:v1: prefix, which proves both the configuration and
# the re-encryption of the Secrets that existed before.
# Cleanup has to decrypt again before it restores the manifest: an API server
# without the key can't read encrypted Secrets.
LAB_CLUSTER=ops
NS=treasury
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
ENC_DIR=/etc/kubernetes/enc

lab_params() {
  echo "PROVIDER=$(pick aescbc secretbox)"
  echo "API_KEY=$(rand_suffix 20)"
}

_etcdctl() {
  node_exec "$(control_plane_node)" "ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key $*"
}

# _flag <name> -> value of --<name> in the manifest
_flag() {
  node_exec "$(control_plane_node)" "grep -E -- '^ *- --$1=' $MANIFEST | tail -1 | sed 's/.*--$1=//' | tr -d '\"[:space:]'" 2>/dev/null
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

lab_setup() {
  local cp; cp="$(control_plane_node)"
  if [[ -n "$(_flag encryption-provider-config)" ]]; then
    log_error "kube-apiserver already has --encryption-provider-config (left over from a previous run?). Run cleanup first."
    return 1
  fi
  backup_node_file "$cp" "$MANIFEST"
  ensure_ns "$NS"
  kc -n "$NS" create secret generic bank-api --from-literal=api-key="$API_KEY" \
    --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" create secret generic swift-gateway --from-literal=bic=TRSYDEFFXXX \
    --from-literal=password="$(rand_suffix 16)" --dry-run=client -o yaml | kc apply -f -
}

# _plain_secrets -> etcd keys under /registry/secrets whose value is not encrypted
_plain_secrets() {
  _etcdctl "get --prefix /registry/secrets -w json" 2>/dev/null \
    | jq -r '.kvs[]? | select((.value | @base64d | startswith("k8s:enc:")) | not) | .key | @base64d' 2>/dev/null
}

lab_check() {
  local cp cfg raw plain; cp="$(control_plane_node)"
  cfg="$(_flag encryption-provider-config)"
  check_gate "kube-apiserver has --encryption-provider-config" test -n "$cfg"
  check "The EncryptionConfiguration file exists on $cp ($cfg)" node_exec "$cp" "test -s '$cfg'"
  check_match "The EncryptionConfiguration configures $PROVIDER" \
    "$(node_exec "$cp" "cat '$cfg'" 2>/dev/null | tr -d '\n')" "kind: *EncryptionConfiguration.*$PROVIDER:"
  check_eq "API server answers /readyz" "$(kc --request-timeout=10s get --raw /readyz 2>/dev/null)" "ok"
  raw="$(_etcdctl "get /registry/secrets/$NS/bank-api --print-value-only" 2>/dev/null | head -c 40 | tr -cd '[:print:]')"
  check_match "Secret $NS/bank-api is stored with $PROVIDER in etcd" "$raw" "^k8s:enc:$PROVIDER:v1:"
  check_not "Secret $NS/bank-api is not readable in plain text in etcd" \
    node_exec "$cp" "ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
      get /registry/secrets/$NS/bank-api --print-value-only | grep -aq '$API_KEY'"
  plain="$(_plain_secrets)"
  if [[ -z "$plain" ]] && _etcdctl "get --prefix /registry/secrets --keys-only --limit 1" 2>/dev/null | grep -q /registry/secrets; then
    _pass "Every Secret in the cluster is encrypted in etcd"
  else
    _fail "Every Secret in the cluster is encrypted in etcd" "still plain text: $(head -3 <<<"$plain" | paste -sd' ') ($(grep -c . <<<"$plain") total)"
  fi
  check_eq "Secret $NS/bank-api is still readable through the API" \
    "$(kc --request-timeout=10s -n $NS get secret bank-api -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null)" "$API_KEY"
}

lab_cleanup() {
  local cp cfg old; cp="$(control_plane_node)"
  cfg="$(_flag encryption-provider-config)"
  if [[ -n "$cfg" ]] && node_exec "$cp" "test -f '$cfg'"; then
    # 1. identity first: the API server writes plain text again but can still read the encrypted data.
    log_info "Decrypting the Secrets before the encryption config is removed ..."
    node_exec "$cp" "awk '{
        if (pending) { if (match(\$0, /^ *- /)) print substr(\$0, 1, RLENGTH - 2) \"- identity: {}\"; pending = 0 }
        print
        if (\$0 ~ /^ *providers: *\$/) pending = 1
      }' '$cfg' > /root/cka-decrypt.yaml && cp /root/cka-decrypt.yaml '$cfg' && rm -f /root/cka-decrypt.yaml"
    old="$(_apiserver_id)"
    node_exec "$cp" "crictl stop $old >/dev/null 2>&1" || true
    if _wait_restart "$old"; then
      # 2. Rewrite every Secret, now in plain text.
      kc get secrets -A -o json | kc replace -f - >/dev/null 2>&1 || log_warn "Some Secrets could not be rewritten"
    else
      log_warn "kube-apiserver did not come back with the decrypting config; restoring the manifest anyway"
    fi
  fi
  # 3. Original manifest (no encryption).
  old="$(_apiserver_id)"
  if node_exec "$cp" "test -f /var/lib/cka-lab/backup/_etc_kubernetes_manifests_kube-apiserver.yaml" &&
     ! node_exec "$cp" "cmp -s /var/lib/cka-lab/backup/_etc_kubernetes_manifests_kube-apiserver.yaml $MANIFEST"; then
    restore_node_file "$cp" "$MANIFEST"
    log_info "Waiting for the original kube-apiserver to come back ..."
    _wait_restart "$old" || log_warn "kube-apiserver is not ready yet"
  else
    restore_node_file "$cp" "$MANIFEST"
  fi
  [[ -n "$cfg" ]] && node_exec "$cp" "rm -f '$cfg'"
  node_exec "$cp" "rm -rf $ENC_DIR"
  kc --request-timeout=10s delete namespace "$NS" --ignore-not-found --wait=false
}
