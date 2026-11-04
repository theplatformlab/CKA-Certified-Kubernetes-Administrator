# shellcheck shell=bash
# User certificate via CertificateSigningRequest, kubeconfig and RBAC.
# Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=insights

lab_params() {
  echo "CSR_USER=$(pick anna ben chloe dario emil)"
  echo "RESOURCE=$(pick configmaps services persistentvolumeclaims)"
  echo "VERBS=$(pick get,list get,list,watch)"
}

lab_setup() {
  ensure_ns "$NS"
  kc -n "$NS" create deployment insights-ui --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
  kc delete csr "$CSR_USER" --ignore-not-found >/dev/null
  mkdir -p "$WORKDIR"
  rm -f "$WORKDIR/$CSR_USER".{key,csr,crt,kubeconfig}
}

KCFG() { echo "$WORKDIR/$CSR_USER.kubeconfig"; }
# _as_user <kubectl args...> — kubectl with the user's kubeconfig only (no other config merged in)
_as_user() { KUBECONFIG="$(KCFG)" kubectl --request-timeout=10s "$@"; }
_can() { kc auth can-i "$@" --as "$CSR_USER"; }

lab_check() {
  local cert watch_expect
  cert="$(jp csr "$CSR_USER" '{.status.certificate}')"
  check_gate "CertificateSigningRequest $CSR_USER exists" exists csr "$CSR_USER"
  check_eq "CSR uses signer kubernetes.io/kube-apiserver-client" \
    "$(jp csr "$CSR_USER" '{.spec.signerName}')" "kubernetes.io/kube-apiserver-client"
  check_eq "CSR is approved and a certificate was issued" \
    "$(jp csr "$CSR_USER" '{.status.conditions[?(@.type=="Approved")].status}')$([[ -n "$cert" ]] && echo /issued)" "True/issued"
  check_eq "$CSR_USER.crt is the issued certificate" \
    "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/$CSR_USER.crt")" \
    "$(if [[ -n "$cert" ]]; then base64 -d <<<"$cert" | tr -d '[:space:]'; else echo "<no certificate issued>"; fi)"
  check_eq "$CSR_USER.kubeconfig authenticates as $CSR_USER" \
    "$(_as_user auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null)" "$CSR_USER"
  check_eq "$CSR_USER.kubeconfig: current context uses namespace $NS" \
    "$(_as_user config view --minify -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null)" "$NS"
  check "$CSR_USER.kubeconfig can list pods in $NS" _as_user -n "$NS" get pods
  check "$CSR_USER.kubeconfig can list $RESOURCE in $NS" _as_user -n "$NS" get "$RESOURCE"
  check_contains "$CSR_USER.kubeconfig is forbidden to list pods in default" \
    "$(_as_user -n default get pods 2>&1)" "Forbidden"
  if [[ "$VERBS" == *watch* ]]; then
    check "$CSR_USER can watch pods in $NS" _can watch pods -n "$NS"
  else
    check_not "$CSR_USER cannot watch pods in $NS" _can watch pods -n "$NS"
  fi
  check_not "$CSR_USER cannot delete pods in $NS" _can delete pods -n "$NS"
  check_not "$CSR_USER cannot read secrets in $NS" _can get secrets -n "$NS"
  check_not "$CSR_USER cannot list deployments in $NS" _can list deployments.apps -n "$NS"
}

lab_cleanup() {
  kc delete csr "$CSR_USER" --ignore-not-found
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
