# shellcheck shell=bash
# Which pods are evicted first (QoS classes). Sourced by scripts/lab.sh.
# Two of six Deployments (picked per session) run BestEffort pods. The others
# cover the cases that look different from their class: limits without
# requests (Guaranteed, requests default to the limits), a sidecar without
# resources next to a Guaranteed container (Burstable) and requests only
# (Burstable). Pod names are random, so the check compares the answer with the
# BestEffort pods running right now.
LAB_CLUSTER=practice
NS=telemetry
DEPLOYS="span-collector metric-relay log-forwarder trace-sampler event-archiver probe-runner"

lab_params() {
  local names a b
  read -ra names <<<"$DEPLOYS"
  a="$(rand_int 0 5)"
  b=$(( (a + $(rand_int 1 5)) % 6 ))
  echo "BE_ONE=${names[a]}"
  echo "BE_TWO=${names[b]}"
}

# _deploy <name> <replicas> <containers yaml, indented for the pod spec>
_deploy() {
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $1
  namespace: $NS
spec:
  replicas: $2
  selector:
    matchLabels:
      app: $1
  template:
    metadata:
      labels:
        app: $1
    spec:
      terminationGracePeriodSeconds: 1
      containers:
$3
YAML
}

# _container <name> [resources yaml on one line, e.g. "{limits: {cpu: 50m}}"]
_container() {
  echo "      - name: $1"
  echo "        image: busybox:1.37"
  echo "        command: [\"sh\", \"-c\", \"while true; do sleep 3600; done\"]"
  [[ -n "${2:-}" ]] && echo "        resources: $2"
  return 0
}

lab_setup() {
  local exact="{requests: {cpu: 20m, memory: 32Mi}, limits: {cpu: 20m, memory: 32Mi}}"
  local limits_only="{limits: {cpu: 20m, memory: 32Mi}}"
  local requests_only="{requests: {cpu: 10m, memory: 16Mi}}"
  local d role=0
  ensure_ns "$NS"
  for d in $DEPLOYS; do
    if [[ "$d" == "$BE_ONE" ]]; then
      _deploy "$d" 2 "$(_container main)"
    elif [[ "$d" == "$BE_TWO" ]]; then
      _deploy "$d" 1 "$(_container main; _container helper)"
    else
      case $role in
        0) _deploy "$d" 2 "$(_container main "$exact")" ;;
        1) _deploy "$d" 1 "$(_container main "$limits_only")" ;;
        2) _deploy "$d" 1 "$(_container main "$exact"; _container sidecar)" ;;
        3) _deploy "$d" 1 "$(_container main "$requests_only")" ;;
      esac
      role=$((role + 1))
    fi
  done
  kc -n "$NS" wait --for=condition=Available deployment --all --timeout=120s
}

# _besteffort — running BestEffort pods in the namespace, sorted (terminating ones left out)
_besteffort() {
  jp -n "$NS" pod '{range .items[?(@.status.qosClass=="BestEffort")]}{.metadata.name} {.metadata.deletionTimestamp}{"\n"}{end}' \
    | awk 'NF == 1 {print $1}' | sort
}

lab_check() {
  local live
  live="$(_besteffort)"
  check_gate "evict-first.txt exists" test -s "$WORKDIR/evict-first.txt"
  check_eq "evict-first.txt lists exactly the BestEffort pods" \
    "$(sed 's/[[:space:]]*$//; s/^[[:space:]]*//; s|^pod/||' "$WORKDIR/evict-first.txt" 2>/dev/null | grep -v '^$' | sort -u | paste -sd' ')" \
    "$(paste -sd' ' <<<"$live")"
  check_eq "the workloads were not changed (3 BestEffort pods still run)" "$(grep -c . <<<"$live")" "3"
}
