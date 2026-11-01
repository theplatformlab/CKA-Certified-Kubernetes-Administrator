# shellcheck shell=bash
# kubectl debug for a pod and a node. Sourced by scripts/lab.sh.
# dns-cache runs the cluster's CoreDNS image (distroless, already on every node).
LAB_CLUSTER=practice
NS=debugging
TICKET_FILE=/etc/cka/maintenance-ticket

lab_params() {
  echo "TICKET=CHG-$(rand_int 10000 99999)"
}

lab_setup() {
  local image
  ensure_ns "$NS"
  image="$(jp -n kube-system deploy coredns '{.spec.template.spec.containers[0].image}')"
  # Recreate the pod: ephemeral containers can't be removed from a pod.
  kc -n "$NS" delete pod dns-cache --ignore-not-found --wait=true >/dev/null
  kc -n "$NS" delete pod -l '!run' --ignore-not-found --wait=false >/dev/null 2>&1
  kc -n "$NS" run dns-cache --image="${image:-registry.k8s.io/coredns/coredns:v1.13.1}" -- -dns.port=1053
  node_exec "$(worker_node 1)" "mkdir -p /etc/cka && echo '$TICKET' > $TICKET_FILE"
  kc -n "$NS" wait pod dns-cache --for=condition=Ready --timeout=120s >/dev/null
}

# name, node and image of every node debugger pod in the namespace (they mount / at /host)
_node_debug_pods() {
  kc -n "$NS" get pods -o jsonpath='{range .items[?(@.spec.volumes[0].hostPath.path=="/")]}{.metadata.name} {.spec.nodeName} {.spec.containers[0].image}{"\n"}{end}' 2>/dev/null
}

# _dns_uid — UID of the DNS server process, read from the container runtime on its node.
_dns_uid() {
  local node cid
  node="$(jp -n $NS pod dns-cache '{.spec.nodeName}')"
  cid="$(jp -n $NS pod dns-cache '{.status.containerStatuses[?(@.name=="dns-cache")].containerID}')"
  [[ -n "$node" && -n "$cid" ]] || return 1
  node_exec "$node" "crictl inspect ${cid#containerd://}" 2>/dev/null | jq -r '.info.runtimeSpec.process.user.uid' 2>/dev/null
}

lab_check() {
  local node ec='{.spec.ephemeralContainers[?(@.targetContainerName=="dns-cache")]'
  node="$(worker_node 1)"
  check_gate "kubectl debug was used (ephemeral container in dns-cache or node debugger pod in $NS)" \
    test -n "$(jp -n $NS pod dns-cache '{.spec.ephemeralContainers[*].name}')$(_node_debug_pods)"
  check_contains "dns-cache has an ephemeral busybox:1.37 container targeting container dns-cache (--target)" \
    "$(jp -n $NS pod dns-cache "$ec.image}")" "busybox:1.37"
  check_eq "Pod dns-cache is still Running" "$(jp -n $NS pod dns-cache '{.status.phase}')" "Running"
  check_eq "dns-uid.txt contains the UID of the DNS process" \
    "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/dns-uid.txt")" "$(_dns_uid)"
  check_match "A busybox:1.37 node debugger pod ran on $node in $NS" \
    "$(_node_debug_pods | awk -v n="$node" '$2 == n {print $3}')" "busybox:1.37"
  check_eq "ticket.txt contains the maintenance ticket number" \
    "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/ticket.txt")" "$TICKET"
}

lab_cleanup() {
  node_exec "$(worker_node 1)" "rm -rf /etc/cka" 2>/dev/null || true
}
