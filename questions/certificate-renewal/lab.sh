# shellcheck shell=bash
# Renew control plane certificates. Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
PKI=/etc/kubernetes/pki
STATE_DIR=/var/lib/exam-q10

CERTS="apiserver.crt apiserver-kubelet-client.crt front-proxy-client.crt etcd/server.crt"

lab_setup() {
  mkdir -p "$WORKDIR"
  # Remember the old expiry dates for grading. (Renewed certs are detected by a
  # later notAfter; notBefore is backdated by kubeadm and can't be used.)
  node_exec "$(control_plane_node)" "
    set -e
    mkdir -p $STATE_DIR
    enddate() { date -d \"\$(openssl x509 -noout -enddate -in \$1 | cut -d= -f2)\" +%s; }
    for c in $CERTS; do enddate $PKI/\$c > $STATE_DIR/\$(echo \$c | tr / _); done
    grep client-certificate-data /etc/kubernetes/admin.conf | awk '{print \$2}' | base64 -d > $STATE_DIR/admin.crt
    enddate $STATE_DIR/admin.crt > $STATE_DIR/admin.conf
    date -u -d \"\$(openssl x509 -noout -enddate -in $PKI/apiserver.crt | cut -d= -f2)\" '+%b %d, %Y %H:%M UTC' > $STATE_DIR/old-expiry
  "
}

# _renewed <cert path relative to the pki dir> -> true if it expires later than at exam start
_renewed() {
  node_exec "$(control_plane_node)" "
    old=\$(cat $STATE_DIR/\$(echo $1 | tr / _))
    new=\$(date -d \"\$(openssl x509 -noout -enddate -in $PKI/$1 | cut -d= -f2)\" +%s)
    [ \"\$new\" -gt \"\$old\" ]
  "
}

_admin_conf_renewed() {
  node_exec "$(control_plane_node)" "
    grep client-certificate-data /etc/kubernetes/admin.conf | awk '{print \$2}' | base64 -d > /tmp/admin.crt
    new=\$(date -d \"\$(openssl x509 -noout -enddate -in /tmp/admin.crt | cut -d= -f2)\" +%s)
    [ \"\$new\" -gt \"\$(cat $STATE_DIR/admin.conf)\" ]
  "
}

_serving_renewed() {
  node_exec "$(control_plane_node)" "
    file=\$(openssl x509 -noout -serial -in $PKI/apiserver.crt)
    served=\$(echo | openssl s_client -connect 127.0.0.1:6443 2>/dev/null | openssl x509 -noout -serial)
    [ -n \"\$served\" ] && [ \"\$file\" = \"\$served\" ]
  "
}

lab_check() {
  local cp; cp="$(control_plane_node)"
  local old; old="$(node_exec "$cp" "cat $STATE_DIR/old-expiry" 2>/dev/null)"
  check_gate "apiserver.crt was renewed" _renewed apiserver.crt
  check_contains "expiration.txt has the old expiry date (${old% *:*})" \
    "$(cat "$WORKDIR/expiration.txt" 2>/dev/null)" "${old% *:*}"
  check "apiserver-kubelet-client.crt was renewed" _renewed apiserver-kubelet-client.crt
  check "front-proxy-client.crt was renewed" _renewed front-proxy-client.crt
  check "etcd/server.crt was renewed" _renewed etcd/server.crt
  check "admin.conf was renewed" _admin_conf_renewed
  check "kube-apiserver serves the renewed certificate" _serving_renewed
}

lab_cleanup() {
  # Renewed certificates are valid certificates; nothing to undo.
  node_exec "$(control_plane_node)" "rm -rf $STATE_DIR" || true
}
