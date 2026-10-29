# shellcheck shell=bash
# Exercise 02 — Multi-container pod with a native sidecar. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=exercise-02

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  local sc='{.spec.initContainers[?(@.name=="log-agent")]'
  local app='{.spec.containers[?(@.name=="app")]'
  check "Pod logger exists in $NS" exists -n $NS pod logger
  check_eq "log-agent is an init container with restartPolicy Always (native sidecar)" \
    "$(jp -n $NS pod logger "$sc.restartPolicy}")" "Always"
  check_eq "log-agent runs busybox:1.37" "$(jp -n $NS pod logger "$sc.image}")" "busybox:1.37"
  check_match "log-agent runs 'tail -F /var/log/app/app.log'" \
    "$(jp -n $NS pod logger "$sc.command} $sc.args}")" "tail -F /var/log/app/app\.log"
  check_eq "log-agent mounts log-volume at /var/log/app" \
    "$(jp -n $NS pod logger "$sc.volumeMounts[?(@.name==\"log-volume\")].mountPath}")" "/var/log/app"
  check_eq "Main container app runs busybox:1.37" "$(jp -n $NS pod logger "$app.image}")" "busybox:1.37"
  check_eq "app mounts log-volume at /var/log/app" \
    "$(jp -n $NS pod logger "$app.volumeMounts[?(@.name==\"log-volume\")].mountPath}")" "/var/log/app"
  check_eq "Volume log-volume is an emptyDir" \
    "$(jp -n $NS pod logger '{.spec.volumes[?(@.name=="log-volume")].emptyDir}')" "{}"
  check_eq "Pod logger is Running and Ready (2/2)" \
    "$(jp -n $NS pod logger '{.status.phase}/{.status.conditions[?(@.type=="Ready")].status}')" "Running/True"
  check_eq "Sidecar log-agent is running" \
    "$(jp -n $NS pod logger '{.status.initContainerStatuses[?(@.name=="log-agent")].started}')" "true"
  check_match "Sidecar log-agent logs show the app's lines" \
    "$(kc -n $NS logs logger -c log-agent --tail=5 2>/dev/null)" "[^[:space:]]"
  check_match "app writes a line every 3s (at least 2 lines in app.log)" \
    "$(kc -n $NS exec logger -c app -- sh -c 'wc -l < /var/log/app/app.log' 2>/dev/null | tr -d '[:space:]')" "^([2-9]|[1-9][0-9]+)$"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
