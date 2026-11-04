# shellcheck shell=bash
# Logs of all pods of a Deployment. Sourced by scripts/lab.sh.
# Every container prints a fixed, numbered set of lines (with its pod name)
# once and then sleeps, so the expected file content is known per pod.
LAB_CLUSTER=practice
NS=ingest
WORKER_LINES=40
SHIPPER_LINES=30

lab_params() {
  echo "REPLICAS=$(rand_int 3 4)"
  echo "TAIL=$(pick 5 7 8 12 15)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: collector
  namespace: $NS
spec:
  replicas: $REPLICAS
  selector:
    matchLabels:
      app: collector
  template:
    metadata:
      labels:
        app: collector
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: worker
        image: busybox:1.37
        command: ["sh", "-c", "for i in \$(seq 1 $WORKER_LINES); do echo \"worker \$HOSTNAME line \$i\"; done; while true; do sleep 3600; done"]
      - name: shipper
        image: busybox:1.37
        command: ["sh", "-c", "for i in \$(seq 1 $SHIPPER_LINES); do echo \"shipper \$HOSTNAME batch \$i shipped\"; done; while true; do sleep 3600; done"]
YAML
  kc -n "$NS" rollout status deploy collector --timeout=120s
}

_only_worker() { [[ -s "$1" ]] && ! grep -q "shipper " "$1"; }

lab_check() {
  local all="$WORKDIR/worker-all.log" tail="$WORKDIR/shipper-tail.log" pods p
  local first=$((SHIPPER_LINES - TAIL + 1)) before=$((SHIPPER_LINES - TAIL))
  pods="$(jp -n $NS pod -l app=collector '{.items[*].metadata.name}')"
  check_gate "worker-all.log or shipper-tail.log exists" test -s "$all" -o -s "$tail"
  local ok_all=1 ok_tail=1 ok_prefix=1 n=0
  for p in $pods; do
    n=$((n + 1))
    [[ "$(grep -cE "worker $p line [0-9]+\$" "$all" 2>/dev/null)" == "$WORKER_LINES" ]] || ok_all=0
    grep -qE "shipper $p batch $first shipped\$" "$tail" 2>/dev/null || ok_tail=0
    grep -qE "shipper $p batch $SHIPPER_LINES shipped\$" "$tail" 2>/dev/null || ok_tail=0
    grep -qE "shipper $p batch $before shipped\$" "$tail" 2>/dev/null && ok_tail=0
    [[ "$(grep -cF "[pod/$p/shipper] shipper $p batch" "$tail" 2>/dev/null)" == "$TAIL" ]] || ok_prefix=0
  done
  check_eq "worker-all.log has all $WORKER_LINES lines of container worker of each of the $n pods" "$ok_all" 1
  check "worker-all.log has no lines of container shipper" _only_worker "$all"
  check_eq "shipper-tail.log has exactly the last $TAIL lines of container shipper of each pod" "$ok_tail" 1
  check_eq "shipper-tail.log lines are prefixed with [pod/<pod>/shipper]" "$ok_prefix" 1
  check_eq "shipper-tail.log has $((n * TAIL)) lines in total" "$(grep -c . "$tail" 2>/dev/null)" "$((n * TAIL))"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
