# shellcheck shell=bash
# Install Docker Engine + cri-dockerd on a node. Sourced by scripts/lab.sh.
# Everything happens on the worker node of the runtime cluster (a kind node =
# privileged Debian container with systemd). The kubelet stays on containerd.
LAB_CLUSTER=runtime
CRI_DOCKERD_VERSION=0.4.9
SOCK=/run/cri-dockerd.sock

lab_setup() {
  local node
  node="$(worker_node)"
  node_exec "$node" "true" || { log_error "Node $node not reachable"; return 1; }
}

lab_check() {
  local node
  node="$(worker_node)"

  check_gate "/usr/local/bin/cri-dockerd exists" node_exec "$node" "test -x /usr/local/bin/cri-dockerd"
  check_match "/usr/local/bin/cri-dockerd is version $CRI_DOCKERD_VERSION" \
    "$(node_exec "$node" "/usr/local/bin/cri-dockerd --version 2>&1" 2>/dev/null)" "^cri-dockerd ${CRI_DOCKERD_VERSION//./\\.} "

  check "overlay and br_netfilter are loaded" \
    node_exec "$node" "grep -qw overlay /proc/filesystems && test -d /sys/module/br_netfilter"
  check "/etc/modules-load.d/ loads overlay and br_netfilter at boot" \
    node_exec "$node" "cat /etc/modules-load.d/*.conf | grep -qx overlay && cat /etc/modules-load.d/*.conf | grep -qx br_netfilter"
  check "/etc/sysctl.d/ sets net.bridge.bridge-nf-call-iptables = 1" \
    node_exec "$node" "cat /etc/sysctl.d/*.conf | tr -d ' ' | grep -qx 'net.bridge.bridge-nf-call-iptables=1'"
  check "/etc/sysctl.d/ sets net.ipv4.ip_forward = 1" \
    node_exec "$node" "cat /etc/sysctl.d/*.conf | tr -d ' ' | grep -qx 'net.ipv4.ip_forward=1'"
  check_eq "Both settings are active (sysctl)" \
    "$(node_exec "$node" "sysctl -n net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward" 2>/dev/null | tr '\n' ' ')" "1 1 "

  check_eq "docker.service is active and enabled" \
    "$(node_exec "$node" "systemctl is-active docker; systemctl is-enabled docker" 2>/dev/null | tr '\n' ' ')" "active enabled "
  check_eq "Docker uses the systemd cgroup driver (same as the kubelet)" \
    "$(node_exec "$node" "docker info --format '{{.CgroupDriver}}'" 2>/dev/null)" "systemd"

  check_eq "cri-docker.socket is active and enabled" \
    "$(node_exec "$node" "systemctl is-active cri-docker.socket; systemctl is-enabled cri-docker.socket" 2>/dev/null | tr '\n' ' ')" "active enabled "
  check_eq "cri-docker.service is active and enabled" \
    "$(node_exec "$node" "systemctl is-active cri-docker.service; systemctl is-enabled cri-docker.service" 2>/dev/null | tr '\n' ' ')" "active enabled "
  check_match "cri-docker.service starts cri-dockerd with --network-plugin=cni" \
    "$(node_exec "$node" "systemctl show -p ExecStart --value cri-docker.service" 2>/dev/null)" "--network-plugin[= ]cni"
  check "$SOCK is a listening socket" node_exec "$node" "test -S $SOCK"
  check_eq "crictl via unix://$SOCK reports RuntimeName docker" \
    "$(node_exec "$node" "crictl --runtime-endpoint unix://$SOCK version 2>/dev/null | awk '/^RuntimeName/{print \$2}'" 2>/dev/null)" "docker"

  check_eq "The kubelet still uses containerd" \
    "$(jp node "$node" '{.status.nodeInfo.containerRuntimeVersion}' | cut -d: -f1)" "containerd"
  check_eq "$node is still Ready" \
    "$(jp node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
}

lab_cleanup() {
  local node
  node="$(worker_node)"
  node_exec "$node" "
    systemctl disable --now cri-docker.service cri-docker.socket 2>/dev/null || true
    rm -f /etc/systemd/system/cri-docker.service /etc/systemd/system/cri-docker.socket /usr/local/bin/cri-dockerd
    systemctl daemon-reload
    systemctl disable --now docker.service docker.socket 2>/dev/null || true
  "
  echo "  Stopped Docker and removed cri-dockerd on $node. The docker.io package stays installed;"
  echo "  for a pristine node recreate the cluster: ./scripts/init-cluster.sh --profile runtime --recreate"
}
