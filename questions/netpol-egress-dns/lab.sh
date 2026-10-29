# shellcheck shell=bash
# Egress NetworkPolicy with DNS. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=ledger-app
NS2=audit-log
METRICS_PORT=9090

lab_params() {
  echo "AUDIT_PORT=$(pick 8080 8081 8888 9000)"
}

# _web <name> <container port> — Deployment (busybox httpd) + Service on port 80
_web() {
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $1
  namespace: $NS2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $1
  template:
    metadata:
      labels:
        app: $1
    spec:
      containers:
      - name: web
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && echo $1 > /www/index.html && exec httpd -f -p $2 -h /www"]
        ports:
        - containerPort: $2
---
apiVersion: v1
kind: Service
metadata:
  name: $1
  namespace: $NS2
spec:
  selector:
    app: $1
  ports:
  - port: 80
    targetPort: $2
YAML
}

lab_setup() {
  # (The runner only waits for \$NS; a previous cleanup may still be deleting \$NS2.)
  kc wait --for=delete "namespace/$NS2" --timeout=180s >/dev/null 2>&1 || true
  ensure_ns "$NS"
  ensure_ns "$NS2"
  _web audit "$AUDIT_PORT"
  _web metrics "$METRICS_PORT"
  kc apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: $NS
spec:
  podSelector: {}
  policyTypes: [Egress]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: api
        image: busybox:1.37
        command: ["sh", "-c", "while true; do sleep 3600; done"]
YAML
  kc -n "$NS2" rollout status deploy audit --timeout=120s
  kc -n "$NS2" rollout status deploy metrics --timeout=120s
  kc -n "$NS" rollout status deploy api --timeout=120s
}

# _reach <labels> <url> -> OPEN or CLOSED
# (The probes wait a few seconds first: kindnet's policy agent learns a new
# pod's IP and labels with a short delay, and until then lets its traffic pass.)
_reach() {
  probe "$NS" "$1" "sleep 5; if wget -qO- -T 3 $2 >/dev/null 2>&1; then echo OPEN; else echo CLOSED; fi" | tr -d '[:space:]'
}
_resolve() {
  probe "$NS" "$1" "sleep 5; if nslookup -timeout=3 audit.$NS2.svc.cluster.local >/dev/null 2>&1; then echo OPEN; else echo CLOSED; fi" | tr -d '[:space:]'
}

lab_check() {
  check_gate "NetworkPolicy api-egress exists in $NS" exists -n $NS networkpolicy api-egress
  check_eq "default-deny-egress is unchanged (all pods, Egress, no rules)" \
    "$(jp -n $NS networkpolicy default-deny-egress '{.spec.podSelector} {.spec.policyTypes} {.spec.egress}')" '{} ["Egress"] '
  check_eq "api-egress selects app=api" "$(jp -n $NS networkpolicy api-egress '{.spec.podSelector.matchLabels.app}')" "api"
  check_eq "app=api pods can resolve audit.$NS2" "$(_resolve app=api)" "OPEN"
  check_eq "app=api pods reach http://audit.$NS2" "$(_reach app=api "http://audit.$NS2")" "OPEN"
  local mip; mip="$(jp -n $NS2 svc metrics '{.spec.clusterIP}')"
  check_eq "app=api pods cannot reach Service metrics in $NS2" "$(_reach app=api "http://$mip")" "CLOSED"
  local aip; aip="$(jp -n $NS2 pod -l app=audit '{.items[0].status.podIP}')"
  check_eq "Other pods in $NS still cannot reach audit" "$(_reach app=batch "http://$aip:$AUDIT_PORT")" "CLOSED"
  check_eq "Other pods in $NS still cannot resolve names" "$(_resolve app=batch)" "CLOSED"
}

lab_cleanup() {
  kc delete namespace "$NS" "$NS2" --ignore-not-found --wait=false
}
