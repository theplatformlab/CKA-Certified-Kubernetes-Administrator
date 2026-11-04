# shellcheck shell=bash
# Service without endpoints (named targetPort mismatch). Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=catalog

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-api
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog-api
  template:
    metadata:
      labels:
        app: catalog-api
    spec:
      containers:
      - name: api
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && echo catalog-api-ok > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - name: api-http
          containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: catalog-api
  namespace: $NS
spec:
  selector:
    app: catalog-api
  ports:
  - name: http
    port: 80
    targetPort: http
YAML
}

# Ready endpoints of Service catalog-api that have a port (one "x" each).
# With an unresolvable named targetPort the slices list the pods with "ports: null".
_ready_endpoints() {
  kc get endpointslices -n $NS -l kubernetes.io/service-name=catalog-api \
    -o jsonpath='{range .items[*]}{.ports[0].port}:{range .endpoints[?(@.conditions.ready==true)]}x{end}{"\n"}{end}' 2>/dev/null \
    | sed -n 's/^[0-9][0-9]*://p' | tr -d '\n'
}

lab_check() {
  check_gate "Service catalog-api has ready endpoints" test -n "$(_ready_endpoints)"
  check_eq "Service catalog-api has 2 ready endpoints" "$(_ready_endpoints)" "xx"
  check_eq "Service catalog-api still listens on port 80" "$(jp -n $NS svc catalog-api '{.spec.ports[0].port}')" "80"
  check_eq "Deployment catalog-api is unchanged (2 replicas, port api-http 8080)" \
    "$(jp -n $NS deploy catalog-api '{.spec.replicas} {.spec.template.spec.containers[0].ports[0].name} {.spec.template.spec.containers[0].ports[0].containerPort}')" \
    "2 api-http 8080"
  check_contains "http://catalog-api.$NS:80 answers from another namespace" \
    "$(probe default - "wget -qO- -T 5 http://catalog-api.$NS:80")" "catalog-api-ok"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
