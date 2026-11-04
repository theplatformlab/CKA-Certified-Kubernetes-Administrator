# shellcheck shell=bash
# Cluster DNS is down. Sourced by scripts/lab.sh.
# Setup breaks two things: the Corefile uses the removed `proxy` plugin
# (CoreDNS crash-loops; coredns is scaled to 0 first so no old pod keeps the
# good config), and Service kube-dns selects k8s-app=core-dns (no endpoints).
# The original Corefile and replica count are saved on the control plane node.
LAB_CLUSTER=practice
NS=dns-outage
BACKUP_DIR=/var/lib/cka-lab/coredns-troubleshooting

lab_setup() {
  local cp; cp="$(control_plane_node)"
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stock-api
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stock-api
  template:
    metadata:
      labels:
        app: stock-api
    spec:
      containers:
      - name: api
        image: nginx:1.28
---
apiVersion: v1
kind: Service
metadata:
  name: stock-api
  namespace: $NS
spec:
  selector:
    app: stock-api
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: shop-frontend
  namespace: $NS
spec:
  terminationGracePeriodSeconds: 1
  containers:
  - name: shell
    image: busybox:1.37
    command: ["sh", "-c", "while true; do sleep 3600; done"]
YAML
  # Save the original state once (node_exec has no stdin: base64 in the command).
  if ! node_exec "$cp" "test -s $BACKUP_DIR/Corefile"; then
    local b64 replicas
    b64="$(jp -n kube-system configmap coredns '{.data.Corefile}' | base64 -w0)"
    replicas="$(jp -n kube-system deploy coredns '{.spec.replicas}')"
    [[ -n "$b64" && -n "$replicas" ]] || { log_error "Could not read the CoreDNS configuration"; return 1; }
    node_exec "$cp" "mkdir -p $BACKUP_DIR && echo $replicas > $BACKUP_DIR/replicas &&
      echo $b64 | base64 -d > $BACKUP_DIR/Corefile.tmp && mv $BACKUP_DIR/Corefile.tmp $BACKUP_DIR/Corefile"
  fi
  local replicas; replicas="$(node_exec "$cp" "cat $BACKUP_DIR/replicas")"
  kc -n kube-system scale deploy coredns --replicas=0
  kc -n kube-system wait --for=delete pod -l k8s-app=kube-dns --timeout=60s >/dev/null 2>&1 || true
  node_exec "$cp" "cat $BACKUP_DIR/Corefile" | sed 's|^\( *\)forward \. |\1proxy . |' |
    kc -n kube-system create configmap coredns --from-file=Corefile=/dev/stdin --dry-run=client -o yaml |
    kc replace -f -
  kc -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"core-dns"}}}'
  kc -n kube-system scale deploy coredns --replicas="$replicas"
  kc -n "$NS" wait --for=condition=Ready pod/shop-frontend --timeout=120s
}

_corefile() { jp -n kube-system configmap coredns '{.data.Corefile}'; }

_attempted() {
  [[ "$(jp -n kube-system svc kube-dns '{.spec.selector.k8s-app}')" != core-dns ]] ||
    ! grep -qE '^\s*proxy ' <<<"$(_corefile)"
}

_lookup() { probe "$NS" - "nslookup -timeout=3 $1"; }

lab_check() {
  local cp; cp="$(control_plane_node)"
  local corefile; corefile="$(_corefile)"
  check_gate "At least one of the faults was addressed" _attempted
  check_eq "Deployment coredns has all replicas ready" \
    "$(jp -n kube-system deploy coredns '{.status.readyReplicas}/{.spec.replicas}')" \
    "$(jp -n kube-system deploy coredns '{.spec.replicas}/{.spec.replicas}')"
  check_match "The Corefile forwards external names (forward . /etc/resolv.conf)" \
    "$(grep -E '^\s*forward ' <<<"$corefile" | sed 's/^ *//')" '^forward \. /etc/resolv\.conf'
  check_match "The cluster.local zone is still served by the kubernetes plugin" \
    "$(grep -E '^\s*kubernetes ' <<<"$corefile" | sed 's/^ *//')" '^kubernetes cluster\.local( |$)'
  local dns_ip; dns_ip="$(node_exec "$cp" "awk '/^clusterDNS:/{getline; print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null)"
  check_eq "Service kube-dns keeps the ClusterIP the kubelets use ($dns_ip)" \
    "$(jp -n kube-system svc kube-dns '{.spec.clusterIP}')" "${dns_ip:-<unknown>}"
  check_match "Service kube-dns has the CoreDNS pods as endpoints" \
    "$(jp -n kube-system endpointslices -l kubernetes.io/service-name=kube-dns '{.items[*].endpoints[*].addresses[0]}')" "[0-9]"
  local ip; ip="$(jp -n $NS svc stock-api '{.spec.clusterIP}')"
  if [[ -z "$CHECK_GATE" ]]; then
    check_contains "A pod in $NS resolves stock-api to $ip" "$(_lookup stock-api.$NS.svc.cluster.local)" "Address: $ip"
    check "A pod resolves kubernetes.default" _lookup kubernetes.default.svc.cluster.local
  else
    check "A pod in $NS resolves stock-api" false
    check "A pod resolves kubernetes.default" false
  fi
}

lab_cleanup() {
  local cp; cp="$(control_plane_node)"
  if [[ "$(jp -n kube-system svc kube-dns '{.spec.selector.k8s-app}')" == core-dns ]]; then
    kc -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}' >/dev/null
  fi
  if node_exec "$cp" "test -s $BACKUP_DIR/Corefile" 2>/dev/null; then
    log_info "Restoring the original CoreDNS Corefile"
    node_exec "$cp" "cat $BACKUP_DIR/Corefile" |
      kc -n kube-system create configmap coredns --from-file=Corefile=/dev/stdin --dry-run=client -o yaml |
      kc replace -f - >/dev/null
    kc -n kube-system scale deploy coredns --replicas="$(node_exec "$cp" "cat $BACKUP_DIR/replicas")" >/dev/null
    kc -n kube-system rollout restart deployment coredns >/dev/null
    kc -n kube-system rollout status deployment coredns --timeout=120s >/dev/null || true
    node_exec "$cp" "rm -rf $BACKUP_DIR"
  fi
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
