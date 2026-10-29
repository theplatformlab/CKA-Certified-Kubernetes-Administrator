# shellcheck shell=bash
# Canary: two Deployments behind one Service. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=release

lab_params() {
  local v1 v2 pct
  read -r v1 v2 pct <<<"$(pick "4 1 20" "3 1 25" "9 1 10" "8 2 20" "6 2 25")"
  echo "V1=$v1"
  echo "V2=$v2"
  echo "TOTAL=$((v1 + v2))"
  echo "PCT=$pct"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-v1
  namespace: $NS
spec:
  replicas: $TOTAL
  selector:
    matchLabels:
      app: shop
      version: v1
  template:
    metadata:
      labels:
        app: shop
        version: v1
    spec:
      containers:
      - name: shop
        image: nginx:1.28
---
apiVersion: v1
kind: Service
metadata:
  name: shop
  namespace: $NS
spec:
  selector:
    app: shop
    version: v1
  ports:
  - port: 80
YAML
}

# _endpoints <version> -> number of ready endpoints of Service shop backed by pods of that version
_endpoints() {
  local pods
  pods="$(kc -n $NS get pods -l "app=shop,version=$1" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)"
  kc get endpointslices -n $NS -l kubernetes.io/service-name=shop \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.targetRef.name}{"\n"}{end}' 2>/dev/null \
    | grep -cxF -f <(echo "${pods:-none}")
}

lab_check() {
  local t='{.spec.template'
  check_gate "Deployment shop-v2 exists" exists -n $NS deploy shop-v2
  check_eq "shop-v2: image nginx:1.29, pod labels app=shop version=v2" \
    "$(jp -n $NS deploy shop-v2 "$t.spec.containers[0].image} $t.metadata.labels.app} $t.metadata.labels.version}")" "nginx:1.29 shop v2"
  check_eq "shop-v2 has $V2 ready replicas" "$(jp -n $NS deploy shop-v2 '{.spec.replicas}/{.status.readyReplicas}')" "$V2/$V2"
  check_eq "shop-v1 is scaled to $V1 ready replicas and still runs nginx:1.28" \
    "$(jp -n $NS deploy shop-v1 "{.spec.replicas}/{.status.readyReplicas} $t.spec.containers[0].image}")" "$V1/$V1 nginx:1.28"
  check_eq "Service shop selects only app=shop" "$(jp -n $NS svc shop '{.spec.selector}')" '{"app":"shop"}'
  check_eq "Service shop has $V1 ready v1 endpoints" "$(_endpoints v1)" "$V1"
  check_eq "Service shop has $V2 ready v2 endpoints ($PCT%)" "$(_endpoints v2)" "$V2"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
