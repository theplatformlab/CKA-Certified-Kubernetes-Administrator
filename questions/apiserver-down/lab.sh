# shellcheck shell=bash
# API server is down. Sourced by scripts/lab.sh.
# FAULT picks what setup breaks in the kube-apiserver manifest:
#   client-ca  --client-ca-file points to a file that doesn't exist
#   etcd-port  --etcd-servers uses port 2397 instead of etcd's client port 2379
LAB_CLUSTER=ops
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
ETCD_MANIFEST=/etc/kubernetes/manifests/etcd.yaml

lab_params() {
  echo "FAULT=$(pick client-ca etcd-port)"
}

lab_setup() {
  local cp
  cp="$(control_plane_node)"
  backup_node_file "$cp" "$MANIFEST"
  case "${FAULT:-client-ca}" in
    etcd-port)
      node_exec "$cp" "sed -i 's|- --etcd-servers=https://127.0.0.1:2379|- --etcd-servers=https://127.0.0.1:2397|' $MANIFEST" ;;
    *)
      node_exec "$cp" "sed -i 's|- --client-ca-file=/etc/kubernetes/pki/ca.crt|- --client-ca-file=/etc/kubernetes/pki/client-ca.crt|' $MANIFEST" ;;
  esac
}

# 0 when every URL in --etcd-servers is one of etcd's --listen-client-urls.
_etcd_servers_ok() {
  local cp servers listen url
  cp="$(control_plane_node)"
  servers="$(node_exec "$cp" "grep -o -- '--etcd-servers=[^ \"]*' $MANIFEST" 2>/dev/null)"
  servers="${servers#--etcd-servers=}"
  listen="$(node_exec "$cp" "grep -o -- '--listen-client-urls=[^ \"]*' $ETCD_MANIFEST" 2>/dev/null)"
  listen="${listen#--listen-client-urls=}"
  [[ -n "$servers" && -n "$listen" ]] || return 1
  IFS=',' read -ra urls <<<"$servers"
  for url in "${urls[@]}"; do
    [[ ",$listen," == *",$url,"* ]] || return 1
  done
}

lab_check() {
  local cp
  cp="$(control_plane_node)"
  check_gate "API server answers /readyz" kc --request-timeout=10s get --raw /readyz
  check_eq "--client-ca-file points to /etc/kubernetes/pki/ca.crt" \
    "$(node_exec "$cp" "grep -o -- '--client-ca-file=[^ \"]*' $MANIFEST" 2>/dev/null)" \
    "--client-ca-file=/etc/kubernetes/pki/ca.crt"
  check "--etcd-servers points to a URL etcd listens on (--listen-client-urls in etcd.yaml)" _etcd_servers_ok
  check_eq "kube-apiserver pod is Ready" \
    "$(kc --request-timeout=10s -n kube-system get pod "kube-apiserver-$cp" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" "True"
  check "Nodes can be listed" kc --request-timeout=10s get nodes
}

lab_cleanup() {
  restore_node_file "$(control_plane_node)" "$MANIFEST"
}
