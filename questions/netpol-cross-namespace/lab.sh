# shellcheck shell=bash
# NetworkPolicies across namespaces, ingress and egress. Sourced by scripts/lab.sh.
# The check tests real connectivity from probe pods carrying the tier labels.
LAB_CLUSTER=practice
NAMESPACES=(frontend backend database)

lab_params() {
  echo "API_PORT=$(pick 8080 8000 5000)"
}

lab_setup() {
  local ns
  for ns in "${NAMESPACES[@]}"; do
    ensure_ns "$ns"
    kc delete networkpolicy --all -n "$ns" --ignore-not-found >/dev/null
  done
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: frontend
spec:
  replicas: 1
  selector:
    matchLabels: {tier: frontend}
  template:
    metadata:
      labels: {tier: frontend}
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
        ports:
        - {name: http, containerPort: 80}
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: frontend
spec:
  selector: {tier: frontend}
  ports:
  - {name: http, port: 80, targetPort: 80}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: backend
spec:
  replicas: 1
  selector:
    matchLabels: {tier: backend}
  template:
    metadata:
      labels: {tier: backend}
    spec:
      containers:
      - name: api
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && echo backend > /www/index.html && httpd -p 9090 -h /www && exec httpd -f -p $API_PORT -h /www"]
        ports:
        - {name: api, containerPort: $API_PORT}
        - {name: admin, containerPort: 9090}
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: backend
spec:
  selector: {tier: backend}
  ports:
  - {name: api, port: $API_PORT, targetPort: $API_PORT}
  - {name: admin, port: 9090, targetPort: 9090}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels: {tier: database}
  template:
    metadata:
      labels: {tier: database}
    spec:
      containers:
      - name: redis
        image: redis:8.8-alpine
        ports:
        - {name: redis, containerPort: 6379}
---
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: database
spec:
  selector: {tier: database}
  ports:
  - {name: redis, port: 6379, targetPort: 6379}
EOF
  for ns in "${NAMESPACES[@]}"; do
    kc rollout status deployment "$ns" -n "$ns" --timeout=180s
  done
}

# _tests <key>... — a script for one probe pod that prints "<key>=open|blocked" per test.
_tests() {
  local script='t() { k=$1; shift; if sh -c "$*" >/dev/null 2>&1; then echo "$k=open"; else echo "$k=blocked"; fi; }'
  local key cmd
  for key in "$@"; do
    case "$key" in
      dns)      cmd="nslookup kubernetes.default.svc.cluster.local" ;;
      frontend) cmd="wget -qO- -T 3 http://frontend.frontend.svc.cluster.local:80" ;;
      api)      cmd="wget -qO- -T 3 http://backend.backend.svc.cluster.local:$API_PORT" ;;
      admin)    cmd="wget -qO- -T 3 http://backend.backend.svc.cluster.local:9090" ;;
      redis)    cmd="echo PING | nc -w 3 database.database.svc.cluster.local 6379 | grep -q PONG" ;;
    esac
    script+="; t $key '$cmd'"
  done
  echo "$script"
}

# _expect <probe output> <key> <open|blocked> <description>
_expect() {
  check_eq "$4" "$(sed -n "s/^$2=//p" <<<"$1" | head -1)" "$3"
}

lab_check() {
  local ns out policies=""
  for ns in "${NAMESPACES[@]}"; do
    policies+="$(jp -n "$ns" networkpolicy '{.items[*].metadata.name}')"
  done
  check_gate "NetworkPolicies exist in frontend, backend or database" test -n "$policies"

  out="$(probe frontend tier=frontend "$(_tests dns api admin redis)")"
  _expect "$out" dns open "frontend: DNS resolution works"
  _expect "$out" api open "frontend -> backend:$API_PORT is allowed"
  _expect "$out" admin blocked "frontend -> backend:9090 is blocked (only $API_PORT)"
  _expect "$out" redis blocked "frontend -> database:6379 is blocked"

  out="$(probe backend tier=backend "$(_tests dns redis frontend)")"
  _expect "$out" dns open "backend: DNS resolution works"
  _expect "$out" redis open "backend -> database:6379 is allowed (redis answers PONG)"
  _expect "$out" frontend blocked "backend -> frontend:80 is blocked"

  out="$(probe database tier=database "$(_tests dns api)")"
  _expect "$out" dns open "database: DNS resolution works"
  _expect "$out" api blocked "database -> backend:$API_PORT is blocked"

  out="$(probe default tier=frontend "$(_tests api)")"
  _expect "$out" api blocked "a tier=frontend pod in namespace default cannot reach backend:$API_PORT"
}
