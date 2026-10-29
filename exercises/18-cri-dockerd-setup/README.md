# Exercise 18 — CRI-dockerd Installation & Configuration

> Supplemental implementation practice: installing Docker and CRI-dockerd. The CKA curriculum includes cluster setup and runtime interfaces, but does not name this specific runtime as an exam task.
>
> Related: [Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25) | Container runtime setup for kubeadm clusters

Install and configure cri-dockerd as a container runtime for a Kubernetes node. This is common when upgrading clusters that need Docker support or when preparing a mixed-runtime cluster.

## Context

Kubernetes deprecated dockershim in v1.20 and removed it in v1.24. To use Docker Engine as a container runtime, a CRI-compatible adapter such as CRI-dockerd is required. Treat the installation steps in this lab as extra implementation practice, not an exam prediction.

This exercise only installs the runtime and gets the CRI socket running. The kubelet keeps using containerd; switching it to cri-dockerd is [Exercise 26](../26-cri-dockerd-setup/).

## Tasks

Use the runtime cluster (`./scripts/init-cluster.sh --profile runtime`) and work on its worker node `cka-runtime-worker`. Open a root shell on it with `docker exec -it cka-runtime-worker bash` — the kind equivalent of `ssh cka-runtime-worker` + `sudo -i` in the exam. The node is a Debian 13 (trixie) container running systemd, so `apt-get`, `systemctl` and `journalctl` work as on a VM.

1. Load the kernel modules `overlay` and `br_netfilter`, and make them load at boot via a file in `/etc/modules-load.d/`
2. Set `net.bridge.bridge-nf-call-iptables = 1` and `net.ipv4.ip_forward = 1` in a file in `/etc/sysctl.d/` and apply it
3. Install Docker Engine (Debian package `docker.io`); `docker.service` must be enabled and running and use the `systemd` cgroup driver
4. Install the cri-dockerd **v0.4.9** binary (`cri-dockerd-0.4.9.amd64.tgz` from GitHub releases) to `/usr/local/bin/cri-dockerd`
5. Create the systemd units `/etc/systemd/system/cri-docker.service` and `/etc/systemd/system/cri-docker.socket`; cri-dockerd must run with `--network-plugin=cni` and take its socket from systemd
6. Enable and start `cri-docker.socket` and `cri-docker.service`
7. Verify the CRI socket is listening at `/run/cri-dockerd.sock`: `crictl --runtime-endpoint unix:///run/cri-dockerd.sock version` must report `RuntimeName: docker`
8. Leave the kubelet alone — the node must stay `Ready` on containerd

Validate with `./scripts/lab.sh check 18`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Download the latest amd64 release from https://github.com/Mirantis/cri-dockerd/releases
- Use `curl -s https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest` to get the latest version automatically
- The socket path must match what you pass to kubelet: `--cri-socket=unix:///run/cri-dockerd.sock`
- Kernel modules persist only if added to `/etc/modules-load.d/`
- Sysctl configuration in `/etc/sysctl.d/` survives reboots
- Check service status with: `systemctl status cri-docker.service`
- Verify socket exists: `ls -la /run/cri-dockerd.sock`
- Check logs if service fails: `journalctl -u cri-docker.service -n 50`
- The upstream unit files live in the repo under `packaging/systemd/`; the important bit is `ExecStart=... --container-runtime-endpoint fd://`, which makes cri-dockerd use the socket that `cri-docker.socket` opened
- The kind node already runs containerd with a customised `/etc/containerd/config.toml`. `apt-get install docker.io` pulls in Debian's `containerd` package and asks whether to replace that file — keep yours: `apt-get install -y -o Dpkg::Options::=--force-confold docker.io`
- The kind node ships `/usr/sbin/policy-rc.d` (exit 101), so apt does not start services; start Docker yourself
- There is no `wget` or `sudo` on the node; use `curl -LO`, and you are already root
- There are also `.deb` packages on the release page (`cri-dockerd_0.4.9.3-0.debian-bookworm_amd64.deb`); `dpkg -i` installs `/usr/bin/cri-dockerd` plus the unit files in one go. This exercise uses the tarball so you write the units yourself

</details>

## What tripped me up

> I downloaded the wrong architecture (arm64 instead of amd64) because I didn't check my system with `uname -m` first. The binary gave a permission denied error, making me think it was a service issue when it was just the wrong file.
>
> I also tried to manually create the socket file instead of letting the systemd socket unit create it. That doesn't work — the socket file is created automatically when you enable and start the socket unit, not beforehand.
>
> One more thing: I forgot that Docker needs to be running separately. The CRI-dockerd service has `After=docker.service` in the systemd file, which means it starts after Docker but doesn't require it to be running. I needed to `systemctl start docker` first or the CRI-dockerd service would fail immediately with "cannot connect to docker daemon".

## Verify

```bash
./scripts/lab.sh check 18
```

Manual checks (on the node, `docker exec -it cka-runtime-worker bash`):

```bash
# Check kernel modules are loaded
lsmod | grep br_netfilter
grep overlay /proc/filesystems     # overlay may be built into the kernel (WSL2) and missing from lsmod

# Check sysctl parameters are set
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward

# Check Docker and CRI-dockerd are running
docker info --format '{{.CgroupDriver}}'      # systemd
systemctl status cri-docker.service
systemctl status cri-docker.socket

# Verify the socket exists and is listening
ls -la /run/cri-dockerd.sock

# Test CRI socket connectivity (plain `crictl` still talks to containerd, see /etc/crictl.yaml)
crictl --runtime-endpoint unix:///run/cri-dockerd.sock version
```

## Cleanup

Skip the cleanup if you continue with [Exercise 26](../26-cri-dockerd-setup/) — it starts from this state.

```bash
./scripts/lab.sh cleanup 18
```

This stops and disables Docker and cri-dockerd and removes the cri-dockerd binary and units. The `docker.io` package stays installed; for a pristine node recreate the cluster with `./scripts/init-cluster.sh --profile runtime --recreate`.

<details>
<summary>Solution</summary>

All commands run as root on the node (`docker exec -it cka-runtime-worker bash`). On a real node, prefix them with `sudo`.

```bash
# Step 1: Load kernel modules (now and at boot)
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Verify modules are loaded
lsmod | grep br_netfilter
grep overlay /proc/filesystems

# Step 2: Configure sysctl parameters
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Apply the changes
sysctl --system

# Verify parameters are applied
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward

# Step 3: Install Docker (prerequisite for CRI-dockerd)
# --force-confold keeps kind's /etc/containerd/config.toml when Debian's containerd package comes along
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confold docker.io

# Start and enable Docker
systemctl enable --now docker
docker info --format '{{.CgroupDriver}}'      # systemd (cgroup v2 default) — same as the kubelet

# Step 4: Download and install CRI-dockerd
uname -m                                      # x86_64 -> amd64
VER=0.4.9
echo "Installing CRI-dockerd version: $VER"

cd /tmp
curl -fLO https://github.com/Mirantis/cri-dockerd/releases/download/v${VER}/cri-dockerd-${VER}.amd64.tgz
tar xzf cri-dockerd-${VER}.amd64.tgz
install -m 0755 cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd
cri-dockerd --version

# Step 5: Create systemd service file
cat > /etc/systemd/system/cri-docker.service <<'EOF'
[Unit]
Description=CRI Interface for Docker Application Container Engine
Documentation=https://github.com/Mirantis/cri-dockerd
After=network-online.target docker.service
Wants=network-online.target
Requires=cri-docker.socket

[Service]
Type=notify
# fd:// = use the socket opened by cri-docker.socket
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

# Step 6: Create systemd socket file
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

# Step 7: Enable and start CRI-dockerd services
systemctl daemon-reload
systemctl enable --now cri-docker.socket cri-docker.service

# Step 8: Verify services are running
systemctl status cri-docker.service --no-pager
systemctl status cri-docker.socket --no-pager

# Step 9: Verify socket is accessible
ls -la /run/cri-dockerd.sock
crictl --runtime-endpoint unix:///run/cri-dockerd.sock version   # RuntimeName: docker

# Step 10: For kubeadm, use this when initializing or joining:
# kubeadm init --cri-socket unix:///run/cri-dockerd.sock
# Or for joining a node:
# kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --cri-socket unix:///run/cri-dockerd.sock
# Switching an existing node to this socket is Exercise 26.
```

</details>
