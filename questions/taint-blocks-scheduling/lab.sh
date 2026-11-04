# shellcheck shell=bash
# Pods Pending because of a leftover NoSchedule taint. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=analytics
BLOCK=maintenance.example.com/window          # the leftover taint (NoSchedule)
KEEP=team.example.com/analytics               # must stay (PreferNoSchedule)

lab_setup() {
  local node; node="$(worker_node 2)"
  ensure_ns "$NS"
  kc label node "$node" disktype=nvme --overwrite >/dev/null
  kc taint node "$node" "$BLOCK=planned:NoSchedule" --overwrite >/dev/null
  kc taint node "$node" "$KEEP=true:PreferNoSchedule" --overwrite >/dev/null
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: etl-worker
  namespace: $NS
spec:
  replicas: 3
  selector:
    matchLabels:
      app: etl-worker
  template:
    metadata:
      labels:
        app: etl-worker
    spec:
      nodeSelector:
        disktype: nvme
      containers:
      - name: etl
        image: busybox:1.37
        command: ["sh", "-c", "exec sleep 86400"]
YAML
}

lab_check() {
  local node; node="$(worker_node 2)"
  local taints; taints="$(jp node "$node" '{range .spec.taints[*]}{.key}={.value}:{.effect}{" "}{end}')"
  check_gate "Deployment etl-worker has 3 ready replicas" \
    test "$(jp -n $NS deploy etl-worker '{.status.readyReplicas}')" = "3"
  check_eq "All etl-worker pods run on $node" \
    "$(kc -n $NS get pods -l app=etl-worker -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{end}' 2>/dev/null)" "$node $node $node "
  check_not "Taint $BLOCK is removed from $node" test -n "$(echo "$taints" | grep -o "$BLOCK=")"
  check_contains "Taint $KEEP=true:PreferNoSchedule is still on $node" "$taints" "$KEEP=true:PreferNoSchedule"
  check_eq "Node $node keeps label disktype=nvme" "$(jp node "$node" '{.metadata.labels.disktype}')" "nvme"
  check_eq "Deployment etl-worker is unchanged (nodeSelector, no tolerations)" \
    "$(jp -n $NS deploy etl-worker '{.spec.template.spec.nodeSelector.disktype}|{.spec.template.spec.tolerations}')" "nvme|"
}

lab_cleanup() {
  local node; node="$(worker_node 2)"
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc taint node "$node" "$BLOCK-" >/dev/null 2>&1 || true
  kc taint node "$node" "$KEEP-" >/dev/null 2>&1 || true
  kc label node "$node" disktype- >/dev/null 2>&1 || true
}
