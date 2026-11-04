# shellcheck shell=bash
# Read a kubeconfig file. Sourced by scripts/lab.sh.
# Setup writes a self-contained kubeconfig for three made-up clusters into
# WORKDIR (its own throwaway CA and client certificates, nothing touches the
# cluster). The context names hint at the users but don't spell them out, so
# the user of a context has to be looked up. The expected context list and
# current context come from the parameters (a later `use-context` on the file
# doesn't move the goalposts); the certificate is read back from the file.
LAB_CLUSTER=practice
CONTEXTS="ops@fra-prod deploy@fra-prod deploy@fra-staging ci@fra-staging audit@ams-dr"

lab_params() {
  local ctx cur cert
  read -ra ctx <<<"$CONTEXTS"
  cur="$(rand_int 0 4)"
  cert=$(( (cur + $(rand_int 1 4)) % 5 ))
  echo "CURRENT_CTX=${ctx[cur]}"
  echo "CERT_CTX=${ctx[cert]}"
}

KCFG() { echo "$WORKDIR/fleet.kubeconfig"; }

# _ctx_user <context> — the user a context points to (same table as in lab_setup)
_ctx_user() {
  case "$1" in
    ops@fra-prod) echo platform-admin ;;
    deploy@*) echo release-bot ;;
    ci@fra-staging) echo ci-runner ;;
    audit@ams-dr) echo compliance-audit ;;
  esac
}

# _user_cert <user> — that user's client certificate in the file (PEM)
_user_cert() {
  kubectl --kubeconfig "$(KCFG)" config view --raw \
    -o jsonpath="{.users[?(@.name==\"$1\")].user.client-certificate-data}" 2>/dev/null | base64 -d 2>/dev/null
}

lab_setup() {
  local tmp kc_file u c cl ns
  mkdir -p "$WORKDIR"
  rm -f "$WORKDIR"/{contexts.txt,current-context.txt,client.crt}
  kc_file="$(KCFG)"
  rm -f "$kc_file"
  tmp="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=fleet-ca" \
    -keyout "$tmp/ca.key" -out "$tmp/ca.crt" 2>/dev/null
  for u in platform-admin release-bot ci-runner compliance-audit; do
    openssl req -new -newkey rsa:2048 -nodes -subj "/CN=$u/O=fleet" \
      -keyout "$tmp/$u.key" -out "$tmp/$u.csr" 2>/dev/null
    openssl x509 -req -in "$tmp/$u.csr" -CA "$tmp/ca.crt" -CAkey "$tmp/ca.key" \
      -CAcreateserial -days 365 -out "$tmp/$u.crt" 2>/dev/null
    kubectl config set-credentials "$u" --kubeconfig "$kc_file" --embed-certs \
      --client-certificate "$tmp/$u.crt" --client-key "$tmp/$u.key" >/dev/null
  done
  kubectl config set-cluster fra-prod --kubeconfig "$kc_file" --embed-certs \
    --server https://10.20.0.10:6443 --certificate-authority "$tmp/ca.crt" >/dev/null
  kubectl config set-cluster fra-staging --kubeconfig "$kc_file" --embed-certs \
    --server https://10.20.1.10:6443 --certificate-authority "$tmp/ca.crt" >/dev/null
  kubectl config set-cluster ams-dr --kubeconfig "$kc_file" --embed-certs \
    --server https://10.30.0.10:6443 --certificate-authority "$tmp/ca.crt" >/dev/null
  for c in $CONTEXTS; do
    cl="${c#*@}"
    ns=default; [[ "$c" == deploy@* ]] && ns=releases
    kubectl config set-context "$c" --kubeconfig "$kc_file" \
      --cluster "$cl" --user "$(_ctx_user "$c")" --namespace "$ns" >/dev/null
  done
  kubectl config use-context "$CURRENT_CTX" --kubeconfig "$kc_file" >/dev/null
  rm -rf "$tmp"
}

# _cert_matches — client.crt is the certificate of the user of CERT_CTX
# (a plain check, not check_eq: the expected PEM is too long for the report)
_cert_matches() {
  local expected
  expected="$(_user_cert "$(_ctx_user "$CERT_CTX")" | tr -d '[:space:]')"
  [[ -n "$expected" && "$(tr -d '[:space:]' <"$WORKDIR/client.crt")" == "$expected" ]]
}

lab_check() {
  check_gate "contexts.txt, current-context.txt or client.crt exists" \
    test -s "$WORKDIR/contexts.txt" -o -s "$WORKDIR/current-context.txt" -o -s "$WORKDIR/client.crt"
  check_eq "contexts.txt lists every context name, one per line" \
    "$(sed 's/[[:space:]]*$//; s/^[[:space:]]*//' "$WORKDIR/contexts.txt" 2>/dev/null | grep -v '^$' | sort | paste -sd' ')" \
    "$(tr ' ' '\n' <<<"$CONTEXTS" | sort | paste -sd' ')"
  check_eq "current-context.txt has the current context of fleet.kubeconfig" \
    "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/current-context.txt")" "$CURRENT_CTX"
  check_contains "client.crt is a decoded PEM certificate" \
    "$(cat "$WORKDIR/client.crt" 2>/dev/null)" "-----BEGIN CERTIFICATE-----"
  check "client.crt is the certificate of the user of context $CERT_CTX" _cert_matches
}

lab_cleanup() {
  rm -f "$(KCFG)"
}
