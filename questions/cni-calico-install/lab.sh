# shellcheck shell=bash
# Install Calico with the Tigera operator. Sourced by scripts/lab.sh.
# The cni cluster is created without a CNI (nodes NotReady, podSubnet 192.168.0.0/16).
LAB_CLUSTER=cni
NS=calico-test
POD_CIDR=192.168.0.0/16

# _probe_on <node> <labels|-> <command> — like probe, but pinned to a node
# (tolerates the control-plane taint). Used for the cross-node test.
_probe_on() {
  local node="$1" labels="$2" cmd="$3"
  local name="probe-$RANDOM$RANDOM"
  local args=(-n "$NS" run "$name" --image=busybox:1.37 --restart=Never --quiet --rm -i
              --pod-running-timeout=60s --command
              --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$node\",\"tolerations\":[{\"operator\":\"Exists\"}]}}")
  [[ "$labels" != "-" ]] && args+=(--labels="$labels")
  timeout 90 kubectl --context "$CTX" "${args[@]}" -- sh -c "$cmd" </dev/null 2>/dev/null
}

lab_setup() {
  ensure_ns "$NS"
  if exists deployment -n tigera-operator tigera-operator; then
    log_warn "Tigera operator is already installed. For a cluster without CNI: ./scripts/init-cluster.sh --profile cni --recreate"
  else
    echo "  Nodes: $(jp nodes '{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status} {end}')(NotReady until a CNI runs)"
  fi
}

lab_check() {
  check_gate "Deployment tigera-operator in tigera-operator is available" test \
    "$(jp -n tigera-operator deploy tigera-operator '{.status.conditions[?(@.type=="Available")].status}')" == "True"
  check_eq "Installation default has an IP pool with CIDR $POD_CIDR (the cluster's podSubnet)" \
    "$(jp installation default '{.spec.calicoNetwork.ipPools[*].cidr}')" "$POD_CIDR"
  check_eq "TigeraStatus calico is Available" \
    "$(jp tigerastatus calico '{.status.conditions[?(@.type=="Available")].status}')" "True"
  local nodes ready
  nodes="$(jp nodes '{range .items[*]}x{end}')"
  ready="$(jp -n calico-system ds calico-node '{.status.numberReady}')"
  check_eq "calico-node is ready on every node (${#nodes})" "${ready:-0}" "${#nodes}"
  check_eq "calico-kube-controllers is available" \
    "$(jp -n calico-system deploy calico-kube-controllers '{.status.conditions[?(@.type=="Available")].status}')" "True"
  check_eq "All nodes are Ready" \
    "$(jp nodes '{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | sort -u | tr -d '\n')" "True"
  check_eq "CoreDNS has 2 ready replicas" "$(jp -n kube-system deploy coredns '{.status.readyReplicas}')" "2"

  check_eq "Deployment web in $NS has 2 ready replicas" "$(jp -n $NS deploy web '{.status.readyReplicas}')" "2"
  check_eq "Container of web runs nginx:1.28" "$(jp -n $NS deploy web '{.spec.template.spec.containers[0].image}')" "nginx:1.28"
  check_eq "Service web selects app=web on port 80" \
    "$(jp -n $NS svc web '{.spec.selector.app}:{.spec.ports[0].port}')" "web:80"
  local ip
  ip="$(jp -n $NS pods -l app=web '{.items[0].status.podIP}')"
  check_match "web pods get IPs from the Calico pool $POD_CIDR" "$ip" '^192\.168\.'
  check_eq "NetworkPolicy web-allow-access selects app=web" \
    "$(jp -n $NS netpol web-allow-access '{.spec.podSelector.matchLabels.app}')" "web"
  check_eq "NetworkPolicy web-allow-access admits pods with access=true on TCP 80" \
    "$(jp -n $NS netpol web-allow-access '{.spec.ingress[0].from[0].podSelector.matchLabels.access}:{.spec.ingress[0].ports[0].port}')" "true:80"

  if [[ "$(jp tigerastatus calico '{.status.conditions[?(@.type=="Available")].status}')" != "True" || -z "$ip" ]]; then
    check "Connectivity tests (need Calico and the web pods running)" false
    return
  fi
  local cp
  cp="$(control_plane_node)"
  check "Cross-node: a pod (access=true) on $cp reaches web pod $ip:80" \
    _probe_on "$cp" "access=true" "wget -qO- -T 5 http://$ip | grep -q 'Welcome to nginx'"
  check "A pod with access=true reaches Service web.$NS" \
    probe "$NS" "access=true" "wget -qO- -T 5 http://web.$NS | grep -q 'Welcome to nginx'"
  check_not "A pod without access=true is blocked by the NetworkPolicy" \
    probe "$NS" - "wget -qO- -T 5 http://web.$NS"
}

lab_cleanup() {
  echo "  Calico stays installed (removing a CNI leaves the nodes broken)."
  echo "  To practise the installation again: ./scripts/init-cluster.sh --profile cni --recreate"
}
