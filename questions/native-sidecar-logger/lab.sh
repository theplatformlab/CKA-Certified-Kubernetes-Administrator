# shellcheck shell=bash
# Native sidecar container. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=logging

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  local p=app-with-logger
  check_eq "Main container is named nginx and runs nginx:1.28" \
    "$(jp -n $NS pod $p '{.spec.containers[?(@.name=="nginx")].image}')" "nginx:1.28"
  check_eq "logger is a native sidecar (initContainer with restartPolicy Always)" \
    "$(jp -n $NS pod $p '{.spec.initContainers[?(@.name=="logger")].restartPolicy} {.spec.initContainers[?(@.name=="logger")].image}')" \
    "Always busybox:1.37"
  check_eq "Volume logs is an emptyDir" "$(jp -n $NS pod $p '{.spec.volumes[?(@.name=="logs")].emptyDir}')" "{}"
  check_eq "nginx mounts logs at /var/log/nginx" \
    "$(jp -n $NS pod $p '{.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.name=="logs")].mountPath}')" "/var/log/nginx"
  check_eq "logger mounts logs at /logs" \
    "$(jp -n $NS pod $p '{.spec.initContainers[?(@.name=="logger")].volumeMounts[?(@.name=="logs")].mountPath}')" "/logs"
  check_eq "Pod is Ready" "$(jp -n $NS pod $p '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  local marker="exam-check-$RANDOM"
  # Send the request through the main container, whatever it is called, so a
  # wrong container name costs only the name check, not this one as well.
  local main; main="$(jp -n $NS pod $p '{.spec.containers[0].name}')"
  kc -n $NS exec $p -c "${main:-nginx}" -- curl -s "http://localhost/$marker" >/dev/null 2>&1
  sleep 2
  check_contains "Requests show up in the logs of container logger" \
    "$(kc -n $NS logs $p -c logger --tail=50 2>/dev/null)" "$marker"
}
