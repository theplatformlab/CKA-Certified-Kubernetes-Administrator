# shellcheck shell=bash
# Exercise 08 — Node drain and cordon. Sourced by scripts/lab.sh.
# Setup creates Deployment drain-test (3 replicas, emptyDir) and marks the pods
# that start on worker2 with lab-original=true, so the check can prove they were evicted.
LAB_CLUSTER=practice
NS=exercise-08

_node() { worker_node 2; }

lab_setup() {
  local node
  node="$(_node)"
  kc uncordon "$node" >/dev/null
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  # Start from scratch so re-running setup restores the initial pod placement.
  kc -n "$NS" delete deployment drain-test --ignore-not-found
  kc -n "$NS" wait --for=delete pod -l app=drain-test --timeout=90s 2>/dev/null || true
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: drain-test
  namespace: $NS
spec:
  replicas: 3
  selector:
    matchLabels:
      app: drain-test
  template:
    metadata:
      labels:
        app: drain-test
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: drain-test
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts:
        - name: cache
          mountPath: /var/cache/nginx
      volumes:
      - name: cache
        emptyDir: {}
EOF
  kc -n "$NS" rollout status deployment drain-test --timeout=180s
  local pod
  for pod in $(kc -n "$NS" get pods -l app=drain-test --field-selector "spec.nodeName=$node" -o name); do
    kc -n "$NS" label "$pod" lab-original=true --overwrite >/dev/null
  done
  if [[ -z "$(kc -n "$NS" get pods -l app=drain-test,lab-original=true -o name)" ]]; then
    log_warn "No drain-test pod landed on $node; re-run setup to get a meaningful drain."
  fi
  echo "  Deployment drain-test runs $(kc -n "$NS" get pods -l app=drain-test,lab-original=true -o name | wc -l) of 3 pods on $node."
}

lab_check() {
  local node
  node="$(_node)"
  check_eq "Node $node is schedulable again (uncordoned)" \
    "$(jp node "$node" '{.spec.unschedulable}')" ""
  check_eq "Node $node is Ready" \
    "$(jp node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "Pods that ran on $node before the drain were evicted" \
    "$(kc -n $NS get pods -l app=drain-test,lab-original=true -o name 2>/dev/null | wc -l)" "0"
  check_eq "Deployment drain-test is scaled to 6 replicas" "$(jp -n $NS deploy drain-test '{.spec.replicas}')" "6"
  check_eq "Deployment drain-test has 6 ready replicas" "$(jp -n $NS deploy drain-test '{.status.readyReplicas}')" "6"
  check_match "New drain-test pods are scheduled on $node after the uncordon" \
    "$(kc -n $NS get pods -l "app=drain-test,!lab-original" --field-selector "spec.nodeName=$node,status.phase=Running" -o name 2>/dev/null | wc -l)" "^[1-9]"
}

lab_cleanup() {
  kc uncordon "$(_node)" >/dev/null 2>&1 || true
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
