# shellcheck shell=bash
# Collect etcd facts from the control plane. Read-only: the check compares the
# answer file with the live etcd manifest and certificate. Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
MANIFEST=/etc/kubernetes/manifests/etcd.yaml

# _flag <name> -> value of --<name>= in the etcd manifest
_flag() {
  node_exec "$(control_plane_node)" "grep -o -- '--$1=[^ \"]*' $MANIFEST | head -1 | cut -d= -f2-" 2>/dev/null
}

# _answer <key> -> value after "<key>:" in etcd-info.txt (surrounding blanks trimmed)
_answer() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//p" "$WORKDIR/etcd-info.txt" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//'
}

# _utc <date> -> the date as "2027-11-01 21:09:27 UTC", empty if it doesn't parse
_utc() { [[ -n "$1" ]] && date -u -d "$1" '+%F %T UTC' 2>/dev/null; }

lab_setup() {
  mkdir -p "$WORKDIR"
  rm -f "$WORKDIR/etcd-info.txt"
}

lab_check() {
  local cert key auth expiry want_auth
  check_gate "etcd-info.txt exists" test -s "$WORKDIR/etcd-info.txt"
  key="$(_flag key-file)"
  cert="$(_flag cert-file)"
  auth="$(_flag client-cert-auth)"
  expiry="$(node_exec "$(control_plane_node)" "openssl x509 -noout -enddate -in '$cert' | cut -d= -f2" 2>/dev/null)"
  [[ "$auth" == true ]] && want_auth=yes || want_auth=no
  check_eq "key_file is etcd's --key-file" "$(_answer key_file)" "$key"
  # Compared as a point in time: "Nov  1 ..." and "Nov 1 ..." are the same date.
  check_eq "cert_expiry is the notAfter date of $cert ($expiry)" \
    "$(_utc "$(_answer cert_expiry)")" "$(_utc "$expiry" || echo unknown)"
  check_eq "client_cert_auth matches --client-cert-auth=$auth" "$(_answer client_cert_auth | tr '[:upper:]' '[:lower:]')" "$want_auth"
}
