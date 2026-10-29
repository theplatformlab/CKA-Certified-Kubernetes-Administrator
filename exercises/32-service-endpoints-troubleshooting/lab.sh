# shellcheck shell=bash
# Exercise 32 — Troubleshoot a Service with no endpoints. Sourced by scripts/lab.sh.
# Setup creates the Deployment, a Service whose selector does not match, and a test pod.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-32}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments
  namespace: ${NS}
  labels:
    app: payments
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payments
  template:
    metadata:
      labels:
        app: payments
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: payments
  namespace: ${NS}
  labels:
    app: payments
spec:
  selector:
    app: payment
  ports:
  - port: 80
    targetPort: 80
EOF
  # restartPolicy Always (kubectl run's default): the pod must survive the
  # node restarts of a paused and resumed exam. A dead one is replaced.
  if [[ "$(jp -n "$NS" pod netcheck '{.status.phase}')" != Running ]]; then
    kc delete pod netcheck -n "$NS" --ignore-not-found --wait=true >/dev/null
    kc run netcheck -n "$NS" --image=busybox:1.37 --command -- sleep 86400
  fi
  kc rollout status deployment/payments -n "$NS" --timeout=120s
  kc wait pod/netcheck -n "$NS" --for=condition=Ready --timeout=120s
}

lab_check() {
  check_eq "Deployment payments is unchanged: pod label app=payments" \
    "$(jp -n $NS deploy payments '{.spec.selector.matchLabels.app}/{.spec.template.metadata.labels.app}')" "payments/payments"
  check_eq "Deployment payments has 2 ready pods" \
    "$(jp -n $NS deploy payments '{.spec.replicas}/{.status.readyReplicas}')" "2/2"
  check_eq "Service payments selects app=payments" "$(jp -n $NS svc payments '{.spec.selector}')" '{"app":"payments"}'
  check_eq "Service payments: port 80 -> targetPort 80" \
    "$(jp -n $NS svc payments '{.spec.ports[0].port}->{.spec.ports[0].targetPort}')" "80->80"
  check_eq "EndpointSlices of payments list 2 ready endpoints" \
    "$(kc get endpointslices -n $NS -l kubernetes.io/service-name=payments \
        -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}' 2>/dev/null)" "xx"
  check "netcheck resolves payments.$NS.svc.cluster.local" \
    kc exec netcheck -n $NS -- nslookup payments.$NS.svc.cluster.local
  check_match "netcheck gets the nginx welcome page from http://payments" \
    "$(kc exec netcheck -n $NS -- wget -qO- -T 3 http://payments.$NS.svc.cluster.local 2>/dev/null | grep -o 'Welcome to nginx' | head -1)" \
    "Welcome to nginx"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
