# shellcheck shell=bash
# Exercise 29 — Troubleshoot a broken API server (etcd endpoint). Sourced by scripts/lab.sh.
# Setup breaks the cluster: it points kube-apiserver at a wrong etcd endpoint.
LAB_CLUSTER=ops
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
ETCD_MANIFEST=/etc/kubernetes/manifests/etcd.yaml
GOOD_ENDPOINT=https://127.0.0.1:2379
BAD_ENDPOINT=https://127.0.0.1:2397

# kubectl with a short timeout: the API server may be down while checking.
_kc() { kc --request-timeout=5s "$@"; }

_api_up() { _kc get --raw /readyz >/dev/null 2>&1; }

_wait_api() {  # _wait_api up|down <seconds>
  local want="$1" i
  for ((i = 0; i < $2; i += 3)); do
    if [[ "$want" == up ]] && _api_up; then return 0; fi
    if [[ "$want" == down ]] && ! _api_up; then return 0; fi
    sleep 3
  done
  return 1
}

lab_setup() {
  local cp
  cp="$(control_plane_node)"
  node_exec "$cp" "sed -i 's|--etcd-servers=.*|--etcd-servers=${BAD_ENDPOINT}|' $MANIFEST"
  echo "  Waiting for the API server to go down ..."
  if _wait_api down 120; then
    echo "  The API server is broken. Control plane shell: docker exec -it $cp bash"
  else
    log_warn "The API server is still answering — rerun setup or check $MANIFEST on $cp"
  fi
}

lab_check() {
  local cp servers listen
  cp="$(control_plane_node)"
  servers="$(node_exec "$cp" "grep -o -- '--etcd-servers=[^ ]*' $MANIFEST" 2>/dev/null)"
  servers="${servers#--etcd-servers=}"
  listen="$(node_exec "$cp" "grep -o -- '--listen-client-urls=[^ ]*' $ETCD_MANIFEST" 2>/dev/null)"
  listen="${listen#--listen-client-urls=}"

  check "--etcd-servers is set in $MANIFEST" test -n "$servers"
  local url ok=true
  IFS=',' read -ra _urls <<<"$servers"
  for url in "${_urls[@]}"; do
    [[ ",$listen," == *",$url,"* ]] || ok=false
  done
  [[ -z "$servers" ]] && ok=false
  check_eq "--etcd-servers points to a URL etcd listens on (--listen-client-urls in etcd.yaml)" "$ok" "true"

  if ! _api_up; then
    check "API server answers /readyz (kubectl get --raw /readyz)" false
    echo "      Remaining checks need the API server — fix it first."
    return
  fi
  check "API server answers /readyz (kubectl get --raw /readyz)" true
  check_eq "kube-apiserver-$cp is Ready" \
    "$(jp --request-timeout=5s -n kube-system pod "kube-apiserver-$cp" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check "k get nodes works" _kc get nodes
  check "k get pods -A works" _kc get pods -A
  check_eq "All nodes are Ready" \
    "$(jp --request-timeout=5s nodes '{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{" "}{end}' | tr ' ' '\n' | sort -u | tr -d '\n')" "True"
}

lab_cleanup() {
  local cp
  cp="$(control_plane_node)"
  node_exec "$cp" "sed -i 's|--etcd-servers=.*|--etcd-servers=${GOOD_ENDPOINT}|' $MANIFEST"
  echo "  Restored --etcd-servers=${GOOD_ENDPOINT}; waiting for the API server ..."
  _wait_api up 180 || log_warn "API server not ready yet — give it a minute (docker exec $cp crictl ps -a | grep apiserver)"
}
