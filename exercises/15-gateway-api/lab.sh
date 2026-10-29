# shellcheck shell=bash
# Exercise 15 — Gateway API: Gateway and HTTPRoute. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-15}"
GATEWAY_API_VERSION=v1.6.3
GATEWAY_API_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
# GatewayClass created by setup. No controller runs for it — the lab checks the object specs.
GW_CLASS=cka-lab

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  echo "  Installing Gateway API ${GATEWAY_API_VERSION} standard CRDs"
  kc apply --server-side -f "$GATEWAY_API_URL" >/dev/null
  kc wait --for=condition=Established --timeout=60s \
    crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
    crd/httproutes.gateway.networking.k8s.io >/dev/null
  kc apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: ${GW_CLASS}
  labels:
    cka-lab/exercise: "15"
spec:
  controllerName: example.com/cka-lab-gateway-controller
  description: Practice GatewayClass for exercise 15 (no controller running)
EOF
}

lab_check() {
  check_eq "Gateway web-gateway exists in $NS" "$(jp -n $NS gateway web-gateway '{.metadata.name}')" "web-gateway"
  check_eq "Gateway web-gateway uses the existing GatewayClass $GW_CLASS" \
    "$(jp -n $NS gateway web-gateway '{.spec.gatewayClassName}')" "$GW_CLASS"
  check_eq "Gateway web-gateway has one listener on port 80, protocol HTTP" \
    "$(jp -n $NS gateway web-gateway '{range .spec.listeners[*]}{.port}/{.protocol} {end}')" "80/HTTP "

  check_eq "Deployment web runs nginx:1.28" "$(jp -n $NS deploy web '{.spec.template.spec.containers[0].image}')" "nginx:1.28"
  check_eq "Deployment web has 2 replicas" "$(jp -n $NS deploy web '{.spec.replicas}')" "2"
  check_eq "Deployment web has 2 ready pods" "$(jp -n $NS deploy web '{.status.readyReplicas}')" "2"
  check_eq "Service web-svc is ClusterIP on port 80" \
    "$(jp -n $NS svc web-svc '{.spec.type}:{.spec.ports[0].port}')" "ClusterIP:80"
  check_match "web-svc.$NS serves the nginx welcome page" \
    "$(probe $NS - "wget -qO- -T 5 http://web-svc.$NS.svc.cluster.local" | grep -o 'Welcome to nginx' | head -1)" "Welcome to nginx"

  check_match "HTTPRoute web-route has web-gateway (namespace $NS or omitted) as parent" \
    "$(jp -n $NS httproute web-route '{.spec.parentRefs[0].name}/{.spec.parentRefs[0].namespace}')" "^web-gateway/($NS)?$"
  check_eq "HTTPRoute matches path prefix /" \
    "$(jp -n $NS httproute web-route '{.spec.rules[0].matches[0].path.type} {.spec.rules[0].matches[0].path.value}')" "PathPrefix /"
  check_eq "HTTPRoute routes to web-svc on port 80" \
    "$(jp -n $NS httproute web-route '{.spec.rules[0].backendRefs[0].name}:{.spec.rules[0].backendRefs[0].port}')" "web-svc:80"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s || true
  kc delete gatewayclass "$GW_CLASS" --ignore-not-found
  # Remove the CRDs only if nothing else in the cluster still uses them.
  if kc get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    if [[ -z "$(kc get gatewayclasses,gateways,httproutes -A --no-headers 2>/dev/null)" ]]; then
      kc delete -f "$GATEWAY_API_URL" --ignore-not-found >/dev/null || true
      echo "  Removed Gateway API CRDs"
    else
      echo "  Gateway API CRDs kept: other Gateway API objects still exist"
    fi
  fi
}
