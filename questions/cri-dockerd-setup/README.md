# Install Docker Engine and cri-dockerd

**Context:** `kubectl config use-context {{CONTEXT}}`

Prepare node `{{NODE_W1}}` (`ssh {{NODE_W1}}`, you are root there) to run containers through Docker Engine via cri-dockerd. The kubelet keeps using containerd for now: leave it alone, the node must stay `Ready`.

1. Load the kernel modules `overlay` and `br_netfilter`, and make them load at boot via a file in `/etc/modules-load.d/`.
2. Set `net.bridge.bridge-nf-call-iptables = 1` and `net.ipv4.ip_forward = 1` in a file in `/etc/sysctl.d/` and apply it.
3. Install Docker Engine (Debian package `docker.io`). `docker.service` must be enabled and running and use the `systemd` cgroup driver.
4. Install the cri-dockerd v0.4.9 binary (`cri-dockerd-0.4.9.amd64.tgz` from the GitHub releases of `Mirantis/cri-dockerd`) to `/usr/local/bin/cri-dockerd`.
5. Create the systemd units `/etc/systemd/system/cri-docker.service` and `/etc/systemd/system/cri-docker.socket`. cri-dockerd must run with `--network-plugin=cni` and take its socket from systemd. Enable and start both units.
6. `crictl --runtime-endpoint unix:///run/cri-dockerd.sock version` must report `RuntimeName: docker`.

Environment note: the node already runs containerd with a customised `/etc/containerd/config.toml`. Installing `docker.io` pulls in Debian's `containerd` package, which asks whether to replace that file: keep the existing one.

## Hints

- `/etc/modules-load.d/` and `/etc/sysctl.d/` are read at boot: also run `modprobe` and `sysctl --system`.
- `apt-get install -y -o Dpkg::Options::=--force-confold docker.io` keeps the existing containerd config. apt doesn't start services on this node: `systemctl enable --now docker`.
- The upstream unit files live in the cri-dockerd repo under `packaging/systemd/`. The important bit is `ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd:// --network-plugin=cni`: `fd://` makes cri-dockerd use the socket that `cri-docker.socket` opened (`ListenStream=%t/cri-dockerd.sock`).

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_W1}}

# 1. kernel modules, now and at boot
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
modprobe overlay
modprobe br_netfilter

# 2. sysctl
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# 3. Docker Engine, keeping the existing containerd config
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold docker.io
systemctl enable --now docker
docker info --format '{{.CgroupDriver}}'      # systemd

# 4. cri-dockerd binary
uname -m                                      # x86_64 -> amd64
cd /tmp
curl -fLO https://github.com/Mirantis/cri-dockerd/releases/download/v0.4.9/cri-dockerd-0.4.9.amd64.tgz
tar xzf cri-dockerd-0.4.9.amd64.tgz
install -m 0755 cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd
cri-dockerd --version

# 5. systemd units
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
ExecReload=/bin/kill -s HUP $MAINPID
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

# 6. verify
ls -la /run/cri-dockerd.sock
crictl --runtime-endpoint unix:///run/cri-dockerd.sock version   # RuntimeName: docker
```

On a new node you would now pass the socket to kubeadm: `kubeadm join ... --cri-socket unix:///run/cri-dockerd.sock`. The release page also has `.deb` packages; `dpkg -i` installs `/usr/bin/cri-dockerd` and the unit files in one go.

## Pitfalls

- Check `uname -m` before downloading: the arm64 tarball on an amd64 node fails with a confusing error that looks like a service problem.
- Don't create `/run/cri-dockerd.sock` by hand: starting `cri-docker.socket` creates it.
- `After=docker.service` only orders the units, it doesn't start Docker. With Docker stopped, cri-dockerd fails right away with "cannot connect to the Docker daemon".
