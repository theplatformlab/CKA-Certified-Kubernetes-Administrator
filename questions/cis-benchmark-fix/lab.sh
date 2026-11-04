# shellcheck shell=bash
# kube-bench findings on the control plane (profiling, etcd manifest
# permissions) and the worker's kubelet (anonymous auth, AlwaysAllow).
# Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
MANIFESTS=/etc/kubernetes/manifests
KUBELET_CONFIG=/var/lib/kubelet/config.yaml

lab_setup() {
  local cp w; cp="$(control_plane_node)"; w="$(worker_node 1)"
  backup_node_file "$cp" "$MANIFESTS/kube-apiserver.yaml"
  backup_node_file "$cp" "$MANIFESTS/kube-controller-manager.yaml"
  backup_node_file "$w" "$KUBELET_CONFIG"
  node_exec "$cp" "chmod 644 $MANIFESTS/etcd.yaml"
  node_exec "$w" "
    sed -i '/^  anonymous:/{n;s/enabled: false/enabled: true/}; s/^  mode: Webhook/  mode: AlwaysAllow/' $KUBELET_CONFIG
    systemctl restart kubelet
  "
}

# _flag <component> <name> -> value of --<name>= in the static Pod manifest
_flag() {
  node_exec "$(control_plane_node)" "grep -o -- '--$2=[^ \"]*' $MANIFESTS/$1.yaml | head -1 | cut -d= -f2-" 2>/dev/null
}

_configz() { kc --request-timeout=10s get --raw "/api/v1/nodes/$(worker_node 1)/proxy/configz" 2>/dev/null; }

_etcd_manifest_private() {
  local mode; mode="$(node_exec "$(control_plane_node)" "stat -c %a $MANIFESTS/etcd.yaml" 2>/dev/null)"
  [[ -n "$mode" ]] && (( (8#$mode & 8#077) == 0 ))
}

_any_fixed() {
  local cz; cz="$(_configz)"
  _etcd_manifest_private || [[ "$(_flag kube-apiserver profiling)" == false || "$(_flag kube-controller-manager profiling)" == false ]] ||
    [[ "$cz" == *'"anonymous":{"enabled":false}'* || "$cz" == *'"mode":"Webhook"'* ]]
}

# _no_pprof -> the API server answers, but not on /debug/pprof
_no_pprof() {
  kc --request-timeout=10s get --raw /readyz >/dev/null 2>&1 && ! kc --request-timeout=10s get --raw /debug/pprof/ >/dev/null 2>&1
}

# _bench <node> <targets> <checks> -> true if kube-bench reports PASS for every listed check
_bench() {
  local out n; n="$(tr ',' '\n' <<<"$3" | wc -l)"
  out="$(node_exec "$1" "kube-bench run --targets $2 --check $3 2>/dev/null | grep -E '^\[(PASS|FAIL|WARN)\] [0-9]'")"
  [[ "$(grep -c '^\[PASS\]' <<<"$out")" == "$n" ]]
}

lab_check() {
  local cp w cz; cp="$(control_plane_node)"; w="$(worker_node 1)"
  cz="$(_configz)"
  check_gate "At least one of the findings was fixed" _any_fixed
  check "1.1.7: $MANIFESTS/etcd.yaml has permissions 600 or stricter" _etcd_manifest_private
  check_eq "1.2.15: kube-apiserver manifest has --profiling=false" "$(_flag kube-apiserver profiling)" "false"
  check "1.2.15: the running kube-apiserver no longer serves /debug/pprof" _no_pprof
  check "kube-apiserver is ready" kc --request-timeout=10s get --raw /readyz
  check_eq "1.3.2: kube-controller-manager manifest has --profiling=false" "$(_flag kube-controller-manager profiling)" "false"
  check "1.3.2: the running kube-controller-manager has --profiling=false" \
    node_exec "$cp" "pgrep -a -x kube-controller | grep -q -- '--profiling=false'"
  check "4.2.1: kubelet on $w runs with anonymous authentication disabled" grep -qF '"anonymous":{"enabled":false}' <<<"$cz"
  check "4.2.2: kubelet on $w runs with authorization mode Webhook" grep -qF '"mode":"Webhook"' <<<"$cz"
  check_eq "Node $w is Ready" "$(jp node "$w" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check "kube-bench on $cp reports PASS for 1.1.7, 1.2.15, 1.3.2" _bench "$cp" master 1.1.7,1.2.15,1.3.2
  check "kube-bench on $w reports PASS for 4.2.1, 4.2.2" _bench "$w" node 4.2.1,4.2.2
}

lab_cleanup() {
  local cp w; cp="$(control_plane_node)"; w="$(worker_node 1)"
  # Back to the kubeadm defaults; the kubelet restarts changed static Pods.
  restore_node_file "$cp" "$MANIFESTS/kube-apiserver.yaml"
  restore_node_file "$cp" "$MANIFESTS/kube-controller-manager.yaml"
  node_exec "$cp" "chmod 600 $MANIFESTS/etcd.yaml" || true
  restore_node_file "$w" "$KUBELET_CONFIG"
  node_exec "$w" "systemctl restart kubelet" || true
}
