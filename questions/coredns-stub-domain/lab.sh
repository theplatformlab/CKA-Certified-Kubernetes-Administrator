# shellcheck shell=bash
# Forward a private DNS zone in CoreDNS. Sourced by scripts/lab.sh.
# Setup runs a small authoritative CoreDNS for corp.internal (hosts plugin) behind
# a ClusterIP Service and saves the cluster's Corefile on the control plane node;
# cleanup restores it.
LAB_CLUSTER=practice
NS=corp-dns
COREDNS_IMAGE=registry.k8s.io/coredns/coredns:v1.13.1
BACKUP_DIR=/var/lib/cka-lab/coredns-stub-domain
WIKI_IP=10.77.0.10

lab_params() {
  echo "HOST=$(pick registry git vault artifacts)"
  echo "HOST_IP=10.$(rand_int 20 99).$(rand_int 0 254).$(rand_int 2 254)"
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
  kc apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: corp-dns
  namespace: $NS
data:
  Corefile: |
    corp.internal:1053 {
        errors
        hosts {
            $HOST_IP $HOST.corp.internal
            $WIKI_IP wiki.corp.internal
            ttl 60
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: corp-dns
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: corp-dns
  template:
    metadata:
      labels:
        app: corp-dns
    spec:
      containers:
      - name: coredns
        image: $COREDNS_IMAGE
        args: ["-conf", "/etc/coredns/Corefile"]
        ports:
        - containerPort: 1053
          protocol: UDP
        - containerPort: 1053
          protocol: TCP
        volumeMounts:
        - name: config
          mountPath: /etc/coredns
      volumes:
      - name: config
        configMap:
          name: corp-dns
---
apiVersion: v1
kind: Service
metadata:
  name: corp-dns
  namespace: $NS
spec:
  selector:
    app: corp-dns
  ports:
  - name: dns
    port: 53
    targetPort: 1053
    protocol: UDP
  - name: dns-tcp
    port: 53
    targetPort: 1053
    protocol: TCP
YAML
  kc -n "$NS" rollout status deploy corp-dns --timeout=120s
}

_lookup() { probe "$NS" - "nslookup -timeout=3 $1"; }

# _resolves <name> <expected ip> [tries] — retries to allow for the reload delay
_resolves() {
  local i out
  for (( i = 0; i < ${3:-1}; i++ )); do
    out="$(_lookup "$1")"
    [[ "$out" == *"Address: $2"* ]] && return 0
    (( i + 1 < ${3:-1} )) && sleep 10
  done
  return 1
}

lab_check() {
  local corefile; corefile="$(jp -n kube-system configmap coredns '{.data.Corefile}')"
  check_gate "CoreDNS Corefile has a configuration for corp.internal" grep -q "corp\.internal" <<<"$corefile"
  # Not attempted: don't spend minutes on probes (0 tries fails right away).
  local tries=6 once=1
  [[ -n "$CHECK_GATE" ]] && tries=0 once=0
  check "$HOST.corp.internal resolves to $HOST_IP" _resolves "$HOST.corp.internal." "$HOST_IP" "$tries"
  check "wiki.corp.internal resolves to $WIKI_IP" _resolves "wiki.corp.internal." "$WIKI_IP" "$once"
  local kip; kip="$(jp -n default svc kubernetes '{.spec.clusterIP}')"
  check "kubernetes.default.svc.cluster.local still resolves" _resolves "kubernetes.default.svc.cluster.local" "$kip" "$once"
  check_match "The cluster.local zone is still served by the kubernetes plugin" \
    "$(grep -E '^\s*kubernetes ' <<<"$corefile" | sed 's/^ *//')" '^kubernetes cluster\.local( |$)'
  check_eq "Deployment coredns has all replicas ready" \
    "$(jp -n kube-system deploy coredns '{.status.readyReplicas}/{.spec.replicas}')" \
    "$(jp -n kube-system deploy coredns '{.spec.replicas}/{.spec.replicas}')"
  check_eq "corp-dns was not modified (1 ready replica, Service port 53)" \
    "$(jp -n $NS deploy corp-dns '{.status.readyReplicas}') $(jp -n $NS svc corp-dns '{.spec.ports[*].port}')" "1 53 53"
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
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
