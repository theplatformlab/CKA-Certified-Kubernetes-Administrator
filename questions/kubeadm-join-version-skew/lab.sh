# shellcheck shell=bash
# Join a node whose kubelet is too old. Setup starts an extra, unjoined node
# container (as in kubeadm-join-worker), installs kubelet and kubectl of the
# previous minor from pkgs.k8s.io and holds them, then points apt at the
# control plane's minor so the right version is one install away.
# kubeadm stays the node image's binary (same version as the control plane).
# Sourced by scripts/lab.sh.
LAB_CLUSTER=ops
KEYRING=/etc/apt/keyrings/kubernetes-apt-keyring.gpg
APT_LIST=/etc/apt/sources.list.d/kubernetes.list

lab_params() {
  echo "JOIN_NAME=worker$(rand_int 3 6)"
}

_kc() { kc --request-timeout=10s "$@"; }

_new_node() { echo "${CLUSTER}-${JOIN_NAME}"; }

# Version of the running control plane, e.g. v1.35.1
_cp_version() { _kc get --raw /version 2>/dev/null | sed -n 's/.*"gitVersion": *"\([^"]*\)".*/\1/p'; }

_remove_node() {
  kc delete node "$(_new_node)" --ignore-not-found --wait=false >/dev/null 2>&1
  docker rm -f -v "$(_new_node)" >/dev/null 2>&1 || true
}

# _use_repo <node> <minor, e.g. v1.34> — pkgs.k8s.io repo of that minor as the only Kubernetes repo
_use_repo() {
  node_exec "$1" "
    set -e
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/$2/deb/Release.key | gpg --dearmor --yes -o $KEYRING
    echo 'deb [signed-by=$KEYRING] https://pkgs.k8s.io/core:/stable:/$2/deb/ /' > $APT_LIST
    apt-get update -qq
  "
}

lab_setup() {
  local cp node image network i version minor old
  cp="$(control_plane_node)"
  node="$(_new_node)"
  version="$(_cp_version)"
  [[ "$version" =~ ^v1\.([0-9]+)\. ]] || { log_error "Cannot read the control plane version"; return 1; }
  minor="v1.${BASH_REMATCH[1]}"
  old="v1.$(( BASH_REMATCH[1] - 1 ))"
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
  echo "  Installing kubelet and kubectl $old on $node (control plane: $version) ..."
  node_exec "$node" "export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq curl gpg >/dev/null" &&
    _use_repo "$node" "$old" &&
    # The node image's own binaries are not dpkg packages; the packages replace them.
    # kind ships its own kubelet unit and /etc/default/kubelet: keep them.
    node_exec "$node" "
      set -e
      export DEBIAN_FRONTEND=noninteractive
      printf 'Dpkg::Options { \"--force-confdef\"; \"--force-confold\"; };\n' > /etc/apt/apt.conf.d/90-keep-config
      v=\$(apt-cache madison kubelet | awk '{print \$3}' | sort -V | tail -1)
      apt-get install -y -qq kubelet=\$v kubectl=\$v >/dev/null
      apt-mark hold kubelet kubectl >/dev/null
    " &&
    _use_repo "$node" "$minor" || {
      log_error "Could not install the packages on $node (no internet access?)"
      return 1
    }
  echo "  $node: kubelet $(node_exec "$node" "kubelet --version | cut -d' ' -f2"), kubeadm $(node_exec "$node" "kubeadm version -o short")"
}

lab_check() {
  local node version
  node="$(_new_node)"
  version="$(_cp_version)"
  check_gate "Node $node is registered" _kc get node "$node"
  check_eq "Node $node is Ready" \
    "$(jp --request-timeout=10s node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "kubelet on $node reports the control plane version (${version:-?})" \
    "$(jp --request-timeout=10s node "$node" '{.status.nodeInfo.kubeletVersion}')" "${version:-unknown}"
  check_eq "kubectl on $node is ${version:-?}" \
    "$(node_exec "$node" "kubectl version --client 2>/dev/null | sed -n 's/^Client Version: //p'" 2>/dev/null)" "${version:-unknown}"
  check "Node $node was joined with kubeadm (kubelet.conf, kubelet config)" \
    node_exec "$node" "test -s /etc/kubernetes/kubelet.conf && test -s /var/lib/kubelet/config.yaml"
  check_eq "kubelet on $node is active and enabled" \
    "$(node_exec "$node" "systemctl is-active kubelet; systemctl is-enabled kubelet" 2>/dev/null | xargs)" "active enabled"
  check_eq "kube-proxy runs on $node" \
    "$(_kc -n kube-system get pods -l k8s-app=kube-proxy --field-selector "spec.nodeName=$node" \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null)" "Running"
}

lab_cleanup() {
  _remove_node
}
