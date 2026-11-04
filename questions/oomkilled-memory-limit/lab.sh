# shellcheck shell=bash
# OOMKilled container: raise the memory limit. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=cache
# Loads ~150 MiB into memory (busybox tail buffers its whole input), then idles.
CMD='echo "loading cache"; head -c 150m /dev/zero | tail > /dev/null; echo "cache loaded"; while true; do sleep 3600; done'

lab_params() {
  echo "MEM_LIMIT=$(pick 256Mi 320Mi 384Mi)"
  echo "MEM_REQ=$(pick 160Mi 192Mi 224Mi)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache-warmer
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cache-warmer
  template:
    metadata:
      labels:
        app: cache-warmer
    spec:
      containers:
      - name: warmer
        image: busybox:1.37
        command: ["sh", "-c", "$(printf '%s' "$CMD" | sed 's/["\\]/\\&/g')"]
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            memory: 128Mi
YAML
}

lab_check() {
  local c='{.spec.template.spec.containers[0]'
  check_gate "Memory limit of cache-warmer was changed" \
    test "$(jp -n $NS deploy cache-warmer "$c.resources.limits.memory}")" != "128Mi"
  check_eq "Memory limit is $MEM_LIMIT" "$(jp -n $NS deploy cache-warmer "$c.resources.limits.memory}")" "$MEM_LIMIT"
  check_eq "Memory request is $MEM_REQ" "$(jp -n $NS deploy cache-warmer "$c.resources.requests.memory}")" "$MEM_REQ"
  check_eq "Image, command and CPU request are unchanged" \
    "$(jp -n $NS deploy cache-warmer "$c.image}|$c.command[2]}|$c.resources.requests.cpu}")" "busybox:1.37|$CMD|50m"
  check_eq "Deployment cache-warmer has 1 updated, ready replica" \
    "$(jp -n $NS deploy cache-warmer '{.status.updatedReplicas}/{.status.readyReplicas}')" "1/1"
  local pod; pod="$(kc -n $NS get pods -l app=cache-warmer -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}' 2>/dev/null)"
  check_eq "The running pod has not restarted" "$(jp -n $NS pod "${pod:-none}" '{.status.containerStatuses[0].restartCount}')" "0"
  check_contains "The cache was loaded" "$(kc -n $NS logs "${pod:-none}" 2>/dev/null)" "cache loaded"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
