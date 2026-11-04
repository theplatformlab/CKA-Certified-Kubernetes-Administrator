# shellcheck shell=bash
# Join a worker node with kubeadm. Setup starts an extra, unjoined node container
# (same image and docker flags as kind's own nodes). Sourced by scripts/lab.sh.
LAB_CLUSTER=ops

lab_params() {
  echo "JOIN_NAME=worker$(rand_int 3 6)"
  echo "POOL=$(pick batch edge gpu reporting)"
}

_new_node() { echo "${CLUSTER}-${JOIN_NAME}"; }

_remove_node() {
  kc delete node "$(_new_node)" --ignore-not-found --wait=false >/dev/null 2>&1
  docker rm -f -v "$(_new_node)" >/dev/null 2>&1 || true
}

lab_setup() {
  local cp node image network i
  cp="$(control_plane_node)"
  node="$(_new_node)"
  image="$(docker inspect -f '{{.Config.Image}}' "$cp")"
  network="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$cp" | awk '{print $1}')"
  _remove_node
  # Same docker flags kind uses for its nodes. The kind cluster label makes
  # `ssh <node>` (exam shim) and `kind delete cluster` treat it like the other nodes.
  docker run -d --name "$node" --hostname "$node" --network "$network" \
    --privileged --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    --security-opt label=disable --cgroupns=private --tmpfs /run --tmpfs /tmp \
    -v /var -v /lib/modules:/lib/modules:ro -e container=docker --restart=on-failure:1 \
    --label "io.x-k8s.kind.cluster=$CLUSTER" --label io.x-k8s.kind.role=worker \
    "$image" >/dev/null
  echo "  Waiting for $node to boot ..."
  for (( i = 0; i < 60; i++ )); do
    node_exec "$node" "systemctl is-system-running 2>/dev/null | grep -Eq 'running|degraded'" 2>/dev/null && break
    sleep 1
  done
  # Same tooling as the other ops nodes (the node image has kubeadm, kubelet and kubectl).
  node_exec "$cp" "cat /etc/apt/sources.list.d/kubernetes.list /etc/apt/apt.conf.d/90-keep-config" >/dev/null 2>&1 &&
    node_exec "$node" "mkdir -p /etc/apt/keyrings" &&
    for f in /etc/apt/keyrings/kubernetes-apt-keyring.gpg /etc/apt/sources.list.d/kubernetes.list /etc/apt/apt.conf.d/90-keep-config; do
      docker exec "$cp" cat "$f" | docker exec -i "$node" sh -c "cat > $f"
    done
}

lab_check() {
  local node ip; node="$(_new_node)"
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$node" 2>/dev/null | awk '{print $1}')"
  check_gate "Node $node is registered" exists node "$node"
  check_eq "Node $node is Ready" "$(jp node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "Node $node has the label pool=$POOL" "$(jp node "$node" '{.metadata.labels.pool}')" "$POOL"
  check_eq "Node $node reports its own address ($ip)" \
    "$(jp node "$node" '{.status.addresses[?(@.type=="InternalIP")].address}')" "$ip"
  check "Node $node was joined with kubeadm (kubelet.conf, kubelet config)" \
    node_exec "$node" "test -s /etc/kubernetes/kubelet.conf && test -s /var/lib/kubelet/config.yaml"
  check_eq "kubelet on $node is active and enabled" \
    "$(node_exec "$node" "systemctl is-active kubelet; systemctl is-enabled kubelet" 2>/dev/null | xargs)" "active enabled"
  check_eq "kube-proxy runs on $node" \
    "$(kc -n kube-system get pods -l k8s-app=kube-proxy --field-selector "spec.nodeName=$node" \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" "Running"
}

lab_cleanup() {
  _remove_node
}
