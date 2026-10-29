# shellcheck shell=bash
# Exercise 17 — kubectl debug (pod and node). Sourced by scripts/lab.sh.
# Both debug sessions leave traces: the ephemeral container stays in the pod
# spec, and the node debugger pod stays (Completed) in the namespace.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-17}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

_node_debug_pods() {
  # name, node and image of every node debugger pod in the namespace
  kc -n "$NS" get pods -o jsonpath='{range .items[?(@.spec.volumes[0].hostPath.path=="/")]}{.metadata.name} {.spec.nodeName} {.spec.containers[0].image}{"\n"}{end}' 2>/dev/null
}

lab_check() {
  local node ec='{.spec.ephemeralContainers[?(@.targetContainerName=="broken-app")]'
  node="$(worker_node 1)"
  check_eq "Pod broken-app runs nginx:1.27" "$(jp -n $NS pod broken-app '{.spec.containers[0].image}')" "nginx:1.27"
  check_eq "Pod broken-app is still Running" "$(jp -n $NS pod broken-app '{.status.phase}')" "Running"
  check_match "broken-app has an ephemeral debug container targeting container broken-app (--target)" \
    "$(jp -n $NS pod broken-app "$ec.name}")" "."
  check_contains "The targeted debug container uses busybox:1.36" \
    "$(jp -n $NS pod broken-app "$ec.image}")" "busybox:1.36"
  check_match "A node debugger pod ran on $node in $NS (host filesystem mounted at /host)" \
    "$(_node_debug_pods | awk -v n="$node" '$2 == n')" "."
  check_match "The node debugger pod uses busybox:1.36" \
    "$(_node_debug_pods | awk -v n="$node" '$2 == n {print $3}')" "^busybox:1.36"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
