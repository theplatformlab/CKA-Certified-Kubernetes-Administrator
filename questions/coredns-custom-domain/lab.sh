# shellcheck shell=bash
# Serve Services under an extra DNS domain. Sourced by scripts/lab.sh.
# Setup saves the cluster's Corefile on the control plane node; cleanup restores it.
# The check resolves both names with a single probe pod, and only when the
# Corefile mentions the new domain.
LAB_CLUSTER=practice
NS=accounting
BACKUP_DIR=/var/lib/cka-lab/coredns-custom-domain

lab_params() {
  echo "DOMAIN=$(pick platform.internal kube.lab corp.cluster)"
}

lab_setup() {
  local cp; cp="$(control_plane_node)"
  ensure_ns "$NS"
  # Remember the original Corefile (only once, so a repeated setup keeps the real original).
  # (node_exec has no stdin, so the content travels base64-encoded in the command.)
  if ! node_exec "$cp" "test -s $BACKUP_DIR/Corefile"; then
    local b64; b64="$(jp -n kube-system configmap coredns '{.data.Corefile}' | base64 -w0)"
    [[ -n "$b64" ]] || { log_error "Could not read the CoreDNS Corefile"; return 1; }
    node_exec "$cp" "mkdir -p $BACKUP_DIR && echo $b64 | base64 -d > $BACKUP_DIR/Corefile.tmp && mv $BACKUP_DIR/Corefile.tmp $BACKUP_DIR/Corefile"
  fi
  rm -f "$WORKDIR/coredns-backup.yaml"
  kc apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: invoices
  namespace: $NS
spec:
  selector:
    app: invoices
  ports:
  - port: 80
    targetPort: 8080
YAML
}

lab_check() {
  local corefile backup="$WORKDIR/coredns-backup.yaml"
  corefile="$(jp -n kube-system configmap coredns '{.data.Corefile}')"
  check_gate "CoreDNS Corefile mentions $DOMAIN" grep -qF "$DOMAIN" <<<"$corefile"

  check "Backup file coredns-backup.yaml exists" test -s "$backup"
  check_eq "Backup is the ConfigMap coredns in kube-system" \
    "$(kc create --dry-run=client -f "$backup" -o jsonpath='{.kind}/{.metadata.namespace}/{.metadata.name}' 2>/dev/null)" \
    "ConfigMap/kube-system/coredns"
  check_eq "Backup holds the original Corefile" \
    "$(kc create --dry-run=client -f "$backup" -o jsonpath='{.data.Corefile}' 2>/dev/null)" \
    "$(node_exec "$(control_plane_node)" "cat $BACKUP_DIR/Corefile" 2>/dev/null)"
  check "kubectl apply accepts the backup (server-side dry run)" kc apply --dry-run=server -f "$backup"

  check_match "The cluster.local zone is still served by the kubernetes plugin" \
    "$(grep -E '^\s*kubernetes ' <<<"$corefile" | sed 's/^ *//')" '^kubernetes cluster\.local( |$)'
  check_eq "Deployment coredns has all replicas ready" \
    "$(jp -n kube-system deploy coredns '{.status.readyReplicas}/{.spec.replicas}')" \
    "$(jp -n kube-system deploy coredns '{.spec.replicas}/{.spec.replicas}')"

  # One probe for both names; not attempted: no probe at all.
  local ip out=""
  ip="$(jp -n $NS svc invoices '{.spec.clusterIP}')"
  [[ -z "$CHECK_GATE" ]] && out="$(probe "$NS" - "nslookup -timeout=3 invoices.$NS.svc.$DOMAIN.; echo ===; nslookup -timeout=3 invoices.$NS.svc.cluster.local.")"
  check "invoices.$NS.svc.$DOMAIN resolves to $ip" grep -qFx "Address: $ip" <<<"${out%%===*}"
  check "invoices.$NS.svc.cluster.local still resolves to $ip" grep -qFx "Address: $ip" <<<"${out#*===}"
}

lab_cleanup() {
  local cp; cp="$(control_plane_node)"
  if node_exec "$cp" "test -s $BACKUP_DIR/Corefile" 2>/dev/null; then
    log_info "Restoring the original CoreDNS Corefile"
    node_exec "$cp" "cat $BACKUP_DIR/Corefile" |
      kc -n kube-system create configmap coredns --from-file=Corefile=/dev/stdin --dry-run=client -o yaml |
      kc replace -f - >/dev/null
    kc -n kube-system rollout restart deployment coredns >/dev/null
    kc -n kube-system rollout status deployment coredns --timeout=120s >/dev/null || true
    node_exec "$cp" "rm -rf $BACKUP_DIR"
  fi
}
