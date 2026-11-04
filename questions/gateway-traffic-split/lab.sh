# shellcheck shell=bash
# Gateway API traffic splitting. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=gateway
GATEWAY_API_VERSION=v1.6.3

_web() {
  kc -n $NS create deployment "$1" --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
  kc -n $NS create service clusterip "$1" --tcp=80:80 --dry-run=client -o yaml | kc apply -f -
}

lab_setup() {
  kc apply --server-side -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null
  kc wait --for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=60s
  kc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: exam-gateway
spec:
  controllerName: example.com/exam-gateway-controller
EOF
  ensure_ns "$NS"
  _web web-v1
  _web web-v2
}

lab_check() {
  local gw="gateways.gateway.networking.k8s.io" rt="httproutes.gateway.networking.k8s.io"
  check_gate "Gateway web-gateway exists" exists -n $NS $gw web-gateway
  check_eq "Gateway uses GatewayClass exam-gateway" "$(jp -n $NS $gw web-gateway '{.spec.gatewayClassName}')" "exam-gateway"
  check_eq "Listener http: HTTP, port 80, hostname web.example.com" \
    "$(jp -n $NS $gw web-gateway '{.spec.listeners[?(@.name=="http")].protocol} {.spec.listeners[?(@.name=="http")].port} {.spec.listeners[?(@.name=="http")].hostname}')" \
    "HTTP 80 web.example.com"
  check_eq "HTTPRoute web-route is attached to web-gateway" "$(jp -n $NS $rt web-route '{.spec.parentRefs[0].name}')" "web-gateway"
  check_eq "HTTPRoute hostname is web.example.com" "$(jp -n $NS $rt web-route '{.spec.hostnames[*]}')" "web.example.com"
  local rule
  rule="$(kc -n $NS get $rt web-route -o json 2>/dev/null | jq -r '
    .spec.rules[] | select(any(.matches[]?; .path.type=="PathPrefix" and .path.value=="/"))
    | [.backendRefs[] | "\(.name):\(.port):\(.weight)"] | sort | join(" ")' 2>/dev/null)"
  check_eq "PathPrefix / goes to web-v1:80 (80) and web-v2:80 (20)" "$rule" "web-v1:80:80 web-v2:80:20"
}

lab_cleanup() {
  kc delete gatewayclass exam-gateway --ignore-not-found >/dev/null 2>&1 || true
}
