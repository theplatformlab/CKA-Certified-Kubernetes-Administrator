# shellcheck shell=bash
# Exercise 26 — Switch a node's kubelet from containerd to cri-dockerd. Sourced by scripts/lab.sh.
# Setup brings the runtime cluster's worker to the end state of exercise 18
# (Docker Engine + cri-dockerd running, kubelet still on containerd) and
# starts a small workload on it.
LAB_CLUSTER=runtime
NS=exercise-26
CRI_DOCKERD_VERSION=0.4.9
SOCK=/run/cri-dockerd.sock
CONTAINERD_SOCK=/run/containerd/containerd.sock

# Exercise 18's solution, non-interactive. Skipped when cri-dockerd already answers.
_prepare_node() {
  local node="$1"
  if node_exec "$node" "crictl --runtime-endpoint unix://$SOCK version >/dev/null 2>&1"; then
    echo "  Docker + cri-dockerd already running on $node (exercise 18 done)"
    return 0
  fi
  echo "  Installing Docker Engine + cri-dockerd v$CRI_DOCKERD_VERSION on $node (exercise 18's solution) ..."
  node_exec "$node" "
    set -euo pipefail
    printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
    modprobe overlay; modprobe br_netfilter
    printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\n' > /etc/sysctl.d/99-kubernetes-cri.conf
    sysctl --system >/dev/null
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq -o Dpkg::Options::=--force-confold docker.io >/dev/null
    systemctl enable --now docker
    cd /tmp
    curl -fsSLO https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
    tar xzf cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
    install -m 0755 cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd
    rm -rf cri-dockerd cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
    cat > /etc/systemd/system/cri-docker.service <<'EOF'
[Unit]
Description=CRI Interface for Docker Application Container Engine
Documentation=https://github.com/Mirantis/cri-dockerd
After=network-online.target docker.service
Wants=network-online.target
Requires=cri-docker.socket

[Service]
Type=notify
ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd:// --network-plugin=cni --pod-infra-container-image=registry.k8s.io/pause:3.10.1
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    cat > /etc/systemd/system/cri-docker.socket <<'EOF'
[Unit]
Description=CRI Docker Socket for the API
PartOf=cri-docker.service

[Socket]
ListenStream=%t/cri-dockerd.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
    systemctl daemon-reload
    systemctl enable --now cri-docker.socket cri-docker.service
  "
}

lab_setup() {
  local node
  node="$(worker_node)"
  _prepare_node "$node"
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" create deployment web --image=nginx:1.28 --replicas=2 --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" expose deployment web --port=80 --dry-run=client -o yaml | kc apply -f -
  echo "  Node $node runtime: $(jp node "$node" '{.status.nodeInfo.containerRuntimeVersion}')"
  echo "  Work on node $node  (shell: docker exec -it $node bash)"
}

lab_check() {
  local node
  node="$(worker_node)"

  check_eq "Kubelet config containerRuntimeEndpoint is unix://$SOCK" \
    "$(node_exec "$node" "awk '/^containerRuntimeEndpoint:/{print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null)" "unix://$SOCK"
  check_eq "kubelet.service is active" "$(node_exec "$node" "systemctl is-active kubelet" 2>/dev/null)" "active"
  check_match "$node reports container runtime docker://" \
    "$(jp node "$node" '{.status.nodeInfo.containerRuntimeVersion}')" "^docker://"
  check_eq "$node is Ready" "$(jp node "$node" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "$node is schedulable again (uncordoned)" "$(jp node "$node" '{.spec.unschedulable}')" ""

  check_eq "kube-proxy and kindnet run on $node" \
    "$(jp -n kube-system pods --field-selector "spec.nodeName=$node,status.phase=Running" \
      '{range .items[*]}{.metadata.ownerReferences[0].name}{"\n"}{end}' | sort | tr '\n' ' ')" "kindnet kube-proxy "
  check_eq "No pod sandboxes left behind in containerd on $node" \
    "$(node_exec "$node" "crictl --runtime-endpoint unix://$CONTAINERD_SOCK pods -q 2>/dev/null | wc -l" 2>/dev/null)" "0"

  check_eq "Deployment web in $NS has 2 ready replicas" "$(jp -n $NS deploy web '{.status.readyReplicas}')" "2"
  check_eq "All web pods run on $node" \
    "$(jp -n $NS pods -l app=web '{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | tr -d '\n')" "$node"
  check_eq "Docker on $node runs 2 nginx containers of the web pods" \
    "$(node_exec "$node" "docker ps --filter label=io.kubernetes.docker.type=container --filter label=io.kubernetes.pod.namespace=$NS -q | wc -l" 2>/dev/null)" "2"
  check "Service web.$NS answers over the pod network" \
    probe "$NS" - "wget -qO- -T 5 http://web.$NS | grep -q 'Welcome to nginx'"
}

lab_cleanup() {
  local node
  node="$(worker_node)"
  kc delete namespace "$NS" --ignore-not-found --wait=false
  if node_exec "$node" "grep -q cri-dockerd.sock /var/lib/kubelet/config.yaml"; then
    echo "  Switching the kubelet on $node back to containerd ..."
    kc drain "$node" --ignore-daemonsets --delete-emptydir-data --force --timeout=120s >/dev/null 2>&1 || true
    node_exec "$node" "
      systemctl stop kubelet
      sed -i 's|^containerRuntimeEndpoint:.*|containerRuntimeEndpoint: unix://$CONTAINERD_SOCK|' /var/lib/kubelet/config.yaml
      crictl --runtime-endpoint unix://$SOCK rmp -fa >/dev/null 2>&1 || true
      echo 'runtime-endpoint: unix://$CONTAINERD_SOCK' > /etc/crictl.yaml
      systemctl start kubelet
    "
    kc uncordon "$node" >/dev/null 2>&1 || true
  fi
  echo "  The kubelet on $node uses containerd. Docker + cri-dockerd stay installed (exercise 18);"
  echo "  ./scripts/lab.sh cleanup 18 stops them, or recreate: ./scripts/init-cluster.sh --profile runtime --recreate"
}
