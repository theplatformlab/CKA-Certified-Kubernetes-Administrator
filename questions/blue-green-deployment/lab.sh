# shellcheck shell=bash
# Blue/green: switch a Service from one Deployment to another. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=web-release

lab_params() {
  echo "REPLICAS=$(rand_int 2 4)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-blue
  namespace: $NS
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: web
      version: blue
  template:
    metadata:
      labels:
        app: web
        version: blue
    spec:
      containers:
      - name: web
        image: nginx:1.28
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: $NS
spec:
  selector:
    app: web
    version: blue
  ports:
  - port: 80
    targetPort: 80
YAML
}

# _endpoints <version> -> number of ready endpoints of Service web backed by pods of that version
_endpoints() {
  local pods
  pods="$(kc -n $NS get pods -l "app=web,version=$1" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)"
  kc get endpointslices -n $NS -l kubernetes.io/service-name=web \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.targetRef.name}{"\n"}{end}' 2>/dev/null \
    | grep -cxF -f <(echo "${pods:-none}")
}

lab_check() {
  local t='{.spec.template'
  check_gate "Deployment web-green exists" exists -n $NS deploy web-green
  check_eq "web-green: image nginx:1.29, pod labels app=web version=green" \
    "$(jp -n $NS deploy web-green "$t.spec.containers[0].image} $t.metadata.labels.app} $t.metadata.labels.version}")" "nginx:1.29 web green"
  check_eq "web-green has $REPLICAS ready replicas" "$(jp -n $NS deploy web-green '{.spec.replicas}/{.status.readyReplicas}')" "$REPLICAS/$REPLICAS"
  check_eq "Service web selects app=web, version=green" "$(jp -n $NS svc web '{.spec.selector}')" '{"app":"web","version":"green"}'
  check_eq "Service web has $REPLICAS ready green endpoints" "$(_endpoints green)" "$REPLICAS"
  check_eq "Service web has no blue endpoints" "$(_endpoints blue)" "0"
  check_eq "Deployment web-blue still exists, unchanged (nginx:1.28), scaled to 0" \
    "$(jp -n $NS deploy web-blue "{.spec.replicas} $t.spec.containers[0].image} $t.metadata.labels.version}")" "0 nginx:1.28 blue"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
