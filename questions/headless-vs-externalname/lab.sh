# shellcheck shell=bash
# Headless and ExternalName Services. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=lookup
NS2=datastore

lab_params() {
  echo "REPLICAS=$(rand_int 2 4)"
  echo "EXT_NAME=$(pick db database pg orders-db)"
}

lab_setup() {
  # (The runner only waits for $NS; a previous cleanup may still be deleting $NS2.)
  kc wait --for=delete "namespace/$NS2" --timeout=180s >/dev/null 2>&1 || true
  ensure_ns "$NS"
  ensure_ns "$NS2"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search
  namespace: $NS
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: search
  template:
    metadata:
      labels:
        app: search
    spec:
      containers:
      - name: search
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && hostname > /www/index.html && exec httpd -f -p 9200 -h /www"]
        ports:
        - containerPort: 9200
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: $NS2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && echo postgres > /www/index.html && exec httpd -f -p 5432 -h /www"]
        ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: $NS2
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
YAML
  kc -n "$NS" rollout status deploy search --timeout=120s
  kc -n "$NS2" rollout status deploy postgres --timeout=120s
}

_lookup() { probe "$NS" - "nslookup -timeout=3 $1"; }

# _all_ips <nslookup output> <ip>... — every IP appears as an Address
_all_ips() {
  local out="$1" ip; shift
  [[ $# -gt 0 ]] || return 1
  for ip in "$@"; do [[ "$out" == *"Address: $ip"* ]] || return 1; done
}

_attempted() { exists -n $NS svc search-headless || exists -n $NS svc "$EXT_NAME"; }

lab_check() {
  check_gate "Service search-headless or $EXT_NAME exists" _attempted
  check_eq "search-headless is headless (clusterIP None) on port 9200" \
    "$(jp -n $NS svc search-headless '{.spec.clusterIP} {.spec.ports[0].port}')" "None 9200"
  local ips out=""
  ips="$(jp -n $NS pod -l app=search '{.items[*].status.podIP}')"
  [[ -z "$CHECK_GATE" ]] && out="$(_lookup search-headless.$NS.svc.cluster.local)"
  # shellcheck disable=SC2086
  check "DNS for search-headless returns all $REPLICAS search pod IPs" _all_ips "$out" $ips
  check_eq "$EXT_NAME is an ExternalName Service" "$(jp -n $NS svc "$EXT_NAME" '{.spec.type}')" "ExternalName"
  check_match "$EXT_NAME points to postgres.$NS2.svc.cluster.local" \
    "$(jp -n $NS svc "$EXT_NAME" '{.spec.externalName}')" "^postgres\\.$NS2\\.svc\\.cluster\\.local\\.?\$"
  local pip; pip="$(jp -n $NS2 svc postgres '{.spec.clusterIP}')"
  out=""
  [[ -z "$CHECK_GATE" ]] && out="$(_lookup "$EXT_NAME.$NS.svc.cluster.local")"
  check_contains "DNS for $EXT_NAME.$NS returns the ClusterIP of postgres ($pip)" "$out" "Address: $pip"
}

lab_cleanup() {
  kc delete namespace "$NS" "$NS2" --ignore-not-found --wait=false
}
