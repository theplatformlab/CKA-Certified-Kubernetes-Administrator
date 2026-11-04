# shellcheck shell=bash
# Pod with labels, requests and limits; relabel it afterwards. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=webshop

lab_params() {
  local mem
  mem="$(pick 64 96 128)"
  echo "MEM_REQ=${mem}Mi"
  echo "MEM_LIM=$(( mem * 2 ))Mi"
  echo "CPU_LIM=$(pick 200 250 300)m"
  echo "VERSION=$(pick v1 v2 v3)"
}

lab_setup() {
  ensure_ns "$NS"
  mkdir -p "$WORKDIR"
}

lab_check() {
  local ip
  check_gate "Pod web exists in $NS" exists -n $NS pod web
  check_eq "Pod web runs image nginx:1.27" "$(jp -n $NS pod web '{.spec.containers[0].image}')" "nginx:1.27"
  check_eq "Pod web is Running and Ready" \
    "$(jp -n $NS pod web '{.status.phase}/{.status.conditions[?(@.type=="Ready")].status}')" "Running/True"
  check_eq "Requests: cpu 100m, memory $MEM_REQ" \
    "$(jp -n $NS pod web '{.spec.containers[0].resources.requests.cpu} {.spec.containers[0].resources.requests.memory}')" \
    "100m $MEM_REQ"
  check_eq "Limits: cpu $CPU_LIM, memory $MEM_LIM" \
    "$(jp -n $NS pod web '{.spec.containers[0].resources.limits.cpu} {.spec.containers[0].resources.limits.memory}')" \
    "$CPU_LIM $MEM_LIM"
  check_eq "Label app=web" "$(jp -n $NS pod web '{.metadata.labels.app}')" "web"
  check_eq "Label version=$VERSION was added" "$(jp -n $NS pod web '{.metadata.labels.version}')" "$VERSION"
  check_eq "Label tier was removed" "$(jp -n $NS pod web '{.metadata.labels.tier}')" ""
  ip="$(jp -n $NS pod web '{.status.podIP}')"
  check_eq "web-ip.txt holds the pod IP${ip:+ ($ip)}" "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/web-ip.txt")" "${ip:-<no pod IP yet>}"
}
