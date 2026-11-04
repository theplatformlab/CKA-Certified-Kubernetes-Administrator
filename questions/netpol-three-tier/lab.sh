# shellcheck shell=bash
# NetworkPolicies for a three-tier app. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=shop

_tier() {
  local name="$1" port="$2" container
  if [[ "$name" == frontend ]]; then
    container="      - name: web
        image: nginx:1.28"
  else
    container="      - name: $name
        image: busybox:1.37
        command: [\"sh\", \"-c\", \"mkdir -p /www && echo $name > /www/index.html && exec httpd -f -p $port -h /www\"]"
  fi
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      tier: $name
  template:
    metadata:
      labels:
        tier: $name
    spec:
      containers:
$container
---
apiVersion: v1
kind: Service
metadata:
  name: $name
  namespace: $NS
spec:
  selector:
    tier: $name
  ports:
  - port: $port
EOF
}

lab_setup() {
  ensure_ns "$NS"
  _tier frontend 80
  _tier backend 3000
  _tier database 5432
}

# _reach <ns> <labels|-> <url> -> prints OPEN or CLOSED (empty if the probe pod failed)
_reach() {
  probe "$1" "$2" "if wget -qO- -T 3 $3 >/dev/null 2>&1; then echo OPEN; else echo CLOSED; fi" | tr -d '[:space:]'
}

lab_check() {
  check_gate "NetworkPolicies exist in shop" test -n "$(jp -n $NS networkpolicy '{.items[*].metadata.name}')"
  check_eq "frontend:80 is reachable from another namespace" \
    "$(_reach default - "http://frontend.$NS:80")" "OPEN"
  check_eq "backend:3000 is reachable from tier=frontend pods" \
    "$(_reach $NS tier=frontend "http://backend:3000")" "OPEN"
  check_eq "backend:3000 is blocked for pods without tier=frontend" \
    "$(_reach $NS app=intruder "http://backend:3000")" "CLOSED"
  check_eq "database:5432 is reachable from tier=backend pods" \
    "$(_reach $NS tier=backend "http://database:5432")" "OPEN"
  check_eq "database:5432 is blocked for tier=frontend pods" \
    "$(_reach $NS tier=frontend "http://database:5432")" "CLOSED"
}
