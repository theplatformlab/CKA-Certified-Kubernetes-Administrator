# shellcheck shell=bash
# Exercise 28 — Complex NetworkPolicy across three namespaces. Sourced by scripts/lab.sh.
# Setup deploys the three tiers; the task is writing the policies. The check tests real
# connectivity from probe pods carrying the tier labels (kindnet enforces NetworkPolicy).
LAB_CLUSTER=practice
NAMESPACES=(frontend backend database)

lab_setup() {
  local ns
  for ns in "${NAMESPACES[@]}"; do
    kc create namespace "$ns" --dry-run=client -o yaml | kc apply -f -
    # Starting state: no policies at all.
    kc delete networkpolicy --all -n "$ns" --ignore-not-found >/dev/null
  done
  kc apply -f - <<'EOF'
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
        # API on 8080, admin endpoint on 9090
        command: ["sh", "-c", "mkdir -p /www && echo backend > /www/index.html && httpd -p 9090 -h /www && exec httpd -f -p 8080 -h /www"]
        ports:
        - {name: api, containerPort: 8080}
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
  - {name: api, port: 8080, targetPort: 8080}
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

# Connectivity tests run inside one probe pod; each prints "<key>=open|blocked".
_T_FRONTEND='http://frontend.frontend.svc.cluster.local:80'
_T_API='http://backend.backend.svc.cluster.local:8080'
_T_ADMIN='http://backend.backend.svc.cluster.local:9090'
_T_DB='database.database.svc.cluster.local 6379'
_tests() {
  # sleep first: probe attaches after the container started, and early output can be lost.
  local script='sleep 2; t() { k=$1; shift; if sh -c "$*" >/dev/null 2>&1; then echo "$k=open"; else echo "$k=blocked"; fi; }'
  local spec key cmd
  for spec in "$@"; do
    key="${spec%%:*}"
    case "$key" in
      dns)      cmd="nslookup kubernetes.default.svc.cluster.local" ;;
      frontend) cmd="wget -qO- -T 3 $_T_FRONTEND" ;;
      api)      cmd="wget -qO- -T 3 $_T_API" ;;
      admin)    cmd="wget -qO- -T 3 $_T_ADMIN" ;;
      redis)    cmd="echo PING | nc -w 3 $_T_DB | grep -q PONG" ;;
    esac
    script+="; t $key '$cmd'"
  done
  echo "$script"
}
# _expect <label> <probe output> <key> <open|blocked> <description>
_expect() {
  local got
  got="$(sed -n "s/^$3=//p" <<<"$2" | head -1)"
  check_eq "$5" "$got" "$4"
}

lab_check() {
  local ns out
  for ns in "${NAMESPACES[@]}"; do
    check_eq "Deployment $ns in namespace $ns is ready" "$(jp -n "$ns" deploy "$ns" '{.status.readyReplicas}')" "1"
  done

  out="$(probe frontend tier=frontend "$(_tests dns api admin redis)")"
  _expect fe "$out" dns open "frontend: DNS resolution works"
  _expect fe "$out" api open "frontend -> backend:8080 is allowed"
  _expect fe "$out" admin blocked "frontend -> backend:9090 is blocked (only 8080)"
  _expect fe "$out" redis blocked "frontend -> database:6379 is blocked"

  out="$(probe backend tier=backend "$(_tests dns redis frontend)")"
  _expect be "$out" dns open "backend: DNS resolution works"
  _expect be "$out" redis open "backend -> database:6379 is allowed (redis answers PONG)"
  _expect be "$out" frontend blocked "backend -> frontend:80 is blocked"

  out="$(probe database tier=database "$(_tests dns api)")"
  _expect db "$out" dns open "database: DNS resolution works"
  _expect db "$out" api blocked "database -> backend:8080 is blocked"

  out="$(probe default tier=frontend "$(_tests api)")"
  _expect other "$out" api blocked "a tier=frontend pod in namespace default cannot reach backend:8080 (namespace must match)"
}

lab_cleanup() {
  kc delete namespace "${NAMESPACES[@]}" --ignore-not-found --wait=false
}
