# shellcheck shell=bash
# Q3 — Node maintenance (drain)
Q_CLUSTER=practice
NS=maintenance

q_setup() {
  local node; node="$(worker_node 2)"
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: $NS
spec:
  replicas: 3
  selector:
    matchLabels:
      app: shop-api
  template:
    metadata:
      labels:
        app: shop-api
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values: [$node]
      containers:
      - name: api
        image: nginx:1.28
---
apiVersion: v1
kind: Pod
metadata:
  name: scratch
  namespace: $NS
spec:
  nodeName: $node
  containers:
  - name: scratch
    image: busybox:1.37
    command: ["sleep", "86400"]
    volumeMounts:
    - name: tmp
      mountPath: /tmp/work
  volumes:
  - name: tmp
    emptyDir: {}
EOF
}

q_check() {
  local node; node="$(worker_node 2)"
  check_gate "Node $node is unschedulable" test "$(jp node "$node" '{.spec.unschedulable}')" = "true"
  local leftover
  leftover="$(kc get pods -A --field-selector "spec.nodeName=$node" \
    -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}:{.metadata.ownerReferences[0].kind}{"\n"}{end}' \
    | grep -v ':DaemonSet$' | grep -v '^$' | tr '\n' ' ')"
  check_eq "Only DaemonSet pods remain on $node" "$leftover" ""
  check_eq "Deployment shop-api has 3 ready replicas" "$(jp -n $NS deploy shop-api '{.status.readyReplicas}')" "3"
  check_not "No shop-api pod runs on $node" \
    bash -c "kubectl --context '$CTX' -n $NS get pods -l app=shop-api -o jsonpath='{.items[*].spec.nodeName}' | grep -qw '$node'"
}
