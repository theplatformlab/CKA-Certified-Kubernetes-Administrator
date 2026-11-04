# shellcheck shell=bash
# Inspect a container with crictl. Sourced by scripts/lab.sh.
# The user creates the pod, so the node and the container ID are only known at
# check time: the ID comes from the pod status, the runtime type from
# `crictl inspect` on the pod's node. nginx writes its entrypoint messages to
# stdout and its own notices to stderr; the log file needs both.
LAB_CLUSTER=practice
NS=forensics

lab_params() {
  echo "POD=$(pick audit-web audit-proxy audit-edge)"
  echo "CASE_ID=case-$(rand_int 1000 9999)"
}

lab_setup() {
  ensure_ns "$NS"
  mkdir -p "$WORKDIR"
  rm -f "$WORKDIR"/{container-info.txt,container.log}
}

# _cid — ID of container web of the pod, without the containerd:// prefix
_cid() {
  local id
  id="$(jp -n "$NS" pod "$POD" '{.status.containerStatuses[?(@.name=="web")].containerID}')"
  echo "${id#*://}"
}

# _id_ok <answer> <container id> — the full ID or a prefix of at least 12 characters
_id_ok() { [[ ${#1} -ge 12 && -n "$2" && "$2" == "$1"* ]]; }

lab_check() {
  local cid node runtime logs id type
  cid="$(_cid)"
  node="$(jp -n "$NS" pod "$POD" '{.spec.nodeName}')"
  runtime=""
  if [[ -n "$cid" && -n "$node" ]]; then
    runtime="$(node_exec "$node" "crictl inspect -o go-template --template '{{.info.runtimeType}}' $cid" 2>/dev/null)"
  fi
  read -r id type _ < <(head -1 "$WORKDIR/container-info.txt" 2>/dev/null)
  logs="$(cat "$WORKDIR/container.log" 2>/dev/null)"
  check_gate "Pod $POD exists in $NS" exists -n "$NS" pod "$POD"
  check_eq "Pod $POD has labels team=forensics and case=$CASE_ID" \
    "$(jp -n "$NS" pod "$POD" '{.metadata.labels.team}/{.metadata.labels.case}')" "forensics/$CASE_ID"
  check_eq "Pod $POD runs container web with image nginx:1.28" \
    "$(jp -n "$NS" pod "$POD" '{.spec.containers[?(@.name=="web")].image}')" "nginx:1.28"
  check_eq "Pod $POD is Running" "$(jp -n "$NS" pod "$POD" '{.status.phase}')" "Running"
  check "container-info.txt starts with the ID of container web" _id_ok "$id" "$cid"
  check_eq "container-info.txt has the runtimeType after the ID" "$type" "${runtime:-<crictl inspect failed>}"
  check_contains "container.log has the stdout of the container" "$logs" "Configuration complete; ready for start up"
  check_contains "container.log has the stderr of the container" "$logs" "start worker processes"
}
