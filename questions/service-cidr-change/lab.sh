# shellcheck shell=bash
# Move new Services to another IP range (ServiceCIDR API, GA since v1.33).
# Setup only backs up the two manifests; cleanup puts them back and rebuilds the
# default ServiceCIDR "kubernetes" with the original range. Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
NS=freight
APISERVER=/etc/kubernetes/manifests/kube-apiserver.yaml
CONTROLLER_MANAGER=/etc/kubernetes/manifests/kube-controller-manager.yaml
BACKUP=/var/lib/cka-lab/backup

lab_params() {
  echo "NEW_RANGE=10.$(pick 112 120 128 140).0.0/16"
}

# The API server restarts during the task: short timeouts, never hang.
_kc() { kc --request-timeout=10s "$@"; }

# _range <manifest path> -> value of --service-cluster-ip-range in it
_range() {
  node_exec "$(control_plane_node)" "grep -o -- '--service-cluster-ip-range=[^ \"]*' $1 | cut -d= -f2" 2>/dev/null
}

# Range the cluster was created with (from the pristine copy setup keeps).
_old_range() { _range "$BACKUP/$(echo "$APISERVER" | tr / _)"; }

# _in_cidr <ip> <cidr> -> true if the IPv4 address lies in the CIDR
_in_cidr() {
  local ip="$1" net="${2%/*}" bits="${2#*/}" a b c d n m
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$2" == */* ]] || return 1
  IFS=. read -r a b c d <<<"$ip"; n=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  IFS=. read -r a b c d <<<"$net"; m=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  (( bits == 0 )) && return 0
  (( (n >> (32 - bits)) == (m >> (32 - bits)) ))
}

_api_up() { _kc get --raw /readyz >/dev/null 2>&1; }

# Pod IP of tracker is among the endpoints of Service $1.
_has_tracker_endpoint() {
  local ip; ip="$(jp --request-timeout=10s -n "$NS" pod tracker '{.status.podIP}')"
  [[ -n "$ip" ]] && _kc -n "$NS" get endpointslices -l "kubernetes.io/service-name=$1" \
    -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | tr ' ' '\n' | grep -qx "$ip"
}

# CIDRs of all ServiceCIDRs that still hand out new IPs (not being deleted).
_open_cidrs() {
  _kc get servicecidrs -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{.spec.cidrs[*]}{"\n"}{end}' 2>/dev/null |
    awk -F'|' '$1 == "" {print $2}' | tr ' ' '\n' | grep . | sort -u | xargs
}

lab_setup() {
  local cp; cp="$(control_plane_node)"
  backup_node_file "$cp" "$APISERVER"
  backup_node_file "$cp" "$CONTROLLER_MANAGER"
  ensure_ns "$NS"
  echo "  Service range now: $(_old_range). New range for the task: $NEW_RANGE"
}

lab_check() {
  local cp old ip
  cp="$(control_plane_node)"
  old="$(_old_range)"
  check_gate "Service tracker-legacy exists in $NS" _kc -n "$NS" get svc tracker-legacy
  check_eq "Pod tracker runs nginx:1.28" \
    "$(jp --request-timeout=10s -n "$NS" pod tracker '{.spec.containers[0].image} {.status.phase}')" "nginx:1.28 Running"
  ip="$(jp --request-timeout=10s -n "$NS" svc tracker-legacy '{.spec.clusterIP}')"
  check "tracker-legacy kept its ClusterIP from the old range $old (${ip:-none})" _in_cidr "$ip" "$old"
  check "tracker-legacy sends traffic to pod tracker" _has_tracker_endpoint tracker-legacy
  check_eq "kube-apiserver has --service-cluster-ip-range=$NEW_RANGE" "$(_range "$APISERVER")" "$NEW_RANGE"
  check_eq "kube-controller-manager has --service-cluster-ip-range=$NEW_RANGE" "$(_range "$CONTROLLER_MANAGER")" "$NEW_RANGE"
  check "API server answers /readyz" _api_up
  check_eq "Only $NEW_RANGE still hands out new ClusterIPs (ServiceCIDRs not being deleted)" "$(_open_cidrs)" "$NEW_RANGE"
  ip="$(jp --request-timeout=10s -n "$NS" svc tracker '{.spec.clusterIP}')"
  check "Service tracker got a ClusterIP from $NEW_RANGE (${ip:-none})" _in_cidr "$ip" "$NEW_RANGE"
  check "tracker sends traffic to pod tracker" _has_tracker_endpoint tracker
  check_eq "kube-dns kept its ClusterIP (the kubelets' clusterDNS)" \
    "$(jp --request-timeout=10s -n kube-system svc kube-dns '{.spec.clusterIP}')" \
    "$(node_exec "$cp" "awk '/^clusterDNS:/{getline; print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null)"
}

# _wait_api_range <range> — until the running API server uses <range> and is ready
_wait_api_range() {
  local i
  for (( i = 0; i < 60; i++ )); do
    if _api_up && [[ "$(jp --request-timeout=5s -n kube-system pod "kube-apiserver-$(control_plane_node)" '{.spec.containers[0].command}')" == *"--service-cluster-ip-range=$1"* ]]; then
      return 0
    fi
    sleep 3
  done
  return 1
}

lab_cleanup() {
  local cp old i ip
  cp="$(control_plane_node)"
  old="$(_old_range)"
  restore_node_file "$cp" "$APISERVER"
  restore_node_file "$cp" "$CONTROLLER_MANAGER"
  [[ -n "$old" ]] || old="$(_range "$APISERVER")"
  echo "  Waiting for the API server with --service-cluster-ip-range=$old ..."
  _wait_api_range "$old" || log_warn "API server not ready yet — run cleanup again in a minute"
  # Free the IPs of the new range first, then put the default ServiceCIDR back.
  _kc delete namespace "$NS" --ignore-not-found --timeout=120s >/dev/null 2>&1 || true
  ip="$(jp --request-timeout=10s svc kubernetes '{.spec.clusterIP}')"
  if [[ -n "$ip" ]] && ! _in_cidr "$ip" "$old"; then
    _kc delete svc kubernetes >/dev/null 2>&1  # the API server recreates it from its range
  fi
  if [[ "$(_kc get servicecidr kubernetes -o jsonpath='{.metadata.deletionTimestamp}|{.spec.cidrs[*]}' 2>/dev/null)" != "|$old" ]]; then
    # A deleted "kubernetes" ServiceCIDR waits until another one covers its IPs.
    # A temporary copy of the old range lets it go; the API server then creates
    # it again from its (restored) flag.
    echo "  Recreating the default ServiceCIDR kubernetes ($old) ..."
    _kc apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: cka-restore
spec:
  cidrs: [$old]
YAML
    for (( i = 0; i < 60; i++ )); do
      [[ "$(_kc get servicecidr kubernetes -o jsonpath='{.metadata.deletionTimestamp}|{.spec.cidrs[*]}' 2>/dev/null)" == "|$old" ]] && break
      sleep 2
    done
  fi
  # Every other ServiceCIDR goes (it stays Terminating while a Service still uses one of its IPs).
  for i in $(_kc get servicecidrs -o name 2>/dev/null | grep -vx 'servicecidr.networking.k8s.io/kubernetes'); do
    _kc delete "$i" --wait=false >/dev/null 2>&1
  done
  local left; left="$(_open_cidrs)"
  [[ "$left" == "$old" ]] || log_warn "ServiceCIDRs still open for new IPs: ${left:-none} (expected $old)"
}
