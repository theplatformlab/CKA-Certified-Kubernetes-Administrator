# shellcheck shell=bash
# Readiness probe on the wrong path/port. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=inventory
CMD='mkdir -p /www && echo stock-api-ok > /www/index.html && echo ok > /www/ready && echo "stock-api listening on :8080, readiness endpoint GET /ready" && exec httpd -f -p 8080 -h /www'

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stock-api
  namespace: $NS
spec:
  replicas: 2
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
        image: busybox:1.37
        command: ["sh", "-c", "$(printf '%s' "$CMD" | sed 's/["\\]/\\&/g')"]
        ports:
        - name: http
          containerPort: 8080
        readinessProbe:
          httpGet:
            path: /healthz
            port: 80
          periodSeconds: 5
          failureThreshold: 3
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
    targetPort: http
YAML
}

_ready_endpoints() {
  kc get endpointslices -n $NS -l kubernetes.io/service-name=stock-api \
    -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}' 2>/dev/null
}

lab_check() {
  local p='{.spec.template.spec.containers[0].readinessProbe'
  check_gate "Service stock-api has ready endpoints" test -n "$(_ready_endpoints)"
  check_eq "Service stock-api has 2 ready endpoints" "$(_ready_endpoints)" "xx"
  check_eq "Readiness probe is an httpGet on path /ready" "$(jp -n $NS deploy stock-api "$p.httpGet.path}")" "/ready"
  check_match "Readiness probe uses port 8080 (or its name http)" "$(jp -n $NS deploy stock-api "$p.httpGet.port}")" '^(8080|http)$'
  check_eq "Image, command, port and Service are unchanged" \
    "$(jp -n $NS deploy stock-api '{.spec.template.spec.containers[0].image}|{.spec.template.spec.containers[0].command[2]}|{.spec.template.spec.containers[0].ports[0].containerPort}')|$(jp -n $NS svc stock-api '{.spec.ports[0].port}/{.spec.ports[0].targetPort}')" \
    "busybox:1.37|$CMD|8080|80/http"
  check_contains "http://stock-api.$NS answers" "$(probe default - "wget -qO- -T 5 http://stock-api.$NS")" "stock-api-ok"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
