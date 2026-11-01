# CKS lab on WSL2

The CKS items run on the `cks` cluster profile (`./scripts/init-cluster.sh --profile cks` creates `cka-cks`; exams use `cka-exam-cks`). kind nodes are containers, so every node uses the kernel of your machine. On Windows that is the WSL2 kernel. Most node-level CKS topics work with it out of the box. AppArmor needs a one-time change to the WSL configuration.

Tested on: WSL2 kernel `6.6.87.2-microsoft-standard-WSL2`, Ubuntu 22.04 distribution, Docker Engine 28.5 inside WSL (not Docker Desktop), kind v0.31, Kubernetes v1.35.1, Falco 0.45.2, gVisor release-20261026.0, trivy 0.76.1, kube-bench 0.16.0.

| Topic | WSL2 default kernel | Status |
|---|---|---|
| Falco (modern eBPF driver) | works | verified |
| seccomp (`RuntimeDefault`, `Localhost` profiles) | works | verified |
| gVisor (`runsc` RuntimeClass) | works | verified |
| kube-bench, trivy, kubesec | work (no kernel dependency) | verified |
| AppArmor | built into the kernel but **not enabled** | needs `.wslconfig` change, see below; **untested** |

## What `--profile cks` installs

| Node | Tools |
|---|---|
| every node | `kube-bench` (configs in `/etc/kube-bench/cfg`), `apparmor` userspace (`apparmor_parser`, `aa-status`) |
| control plane | `trivy` (vulnerability DB downloaded during cluster creation), `kubesec` |
| worker | Falco as systemd service `falco` (modern eBPF), gVisor `runsc` with the containerd runtime handler `runsc` |

kind's `/usr/sbin/policy-rc.d` is removed on the cks nodes, so `apt-get install/purge` starts and stops services like on a real node. Creating the cluster takes about 1.5 minutes on top of the plain kind cluster. It needs internet access: falco.org, gvisor.dev / storage.googleapis.com, github.com and the trivy DB registry (mirror.gcr.io / ghcr.io).

Versions: Falco and gVisor come from their apt repositories (latest). `TRIVY_VERSION`, `KUBE_BENCH_VERSION` and `KUBESEC_VERSION` pin the others (see `scripts/init-cluster.sh`).

## Falco: works (modern eBPF)

The WSL2 kernel has BTF (`/sys/kernel/btf/vmlinux`), which is all the modern eBPF driver needs. No kernel module and no kernel headers are required.

Verified:

1. In a plain privileged Docker container on the WSL host, alerts appear:
   `docker run --rm --privileged --pid=host -v /proc:/host/proc:ro -v /etc:/host/etc:ro -v /sys/kernel/tracing:/sys/kernel/tracing:ro falcosecurity/falco falco -o engine.kind=modern_ebpf`
2. On a kind worker node as a systemd service, like on the exam:
   ```bash
   # what init-cluster.sh does on the worker
   curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
   echo 'deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main' \
     > /etc/apt/sources.list.d/falcosecurity.list
   apt-get update
   FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf FALCOCTL_ENABLED=no apt-get install -y falco
   ```
   The package installs `falco-modern-bpf.service` with the alias `falco`. `journalctl -u` only accepts real unit names, so `init-cluster.sh` copies the unit to a plain `/etc/systemd/system/falco.service`. Then `systemctl restart falco` and `journalctl -u falco` both work.
3. A Pod that runs `cat /etc/shadow` triggers `Sensitive file opened for reading by non-trusted program`, with `k8s_pod_name` and `k8s_ns_name` filled in (the container plugin reads them from the node's containerd). Custom rules in `/etc/falco/falco_rules.local.yaml` work, and so does hot reload on file change (item `falco-runtime-detection`).

Things to know:

- **Falco sees the whole machine.** eBPF programs are kernel-wide, so the Falco on the worker also reports syscalls from other kind clusters, other Docker containers and WSL processes. Alerts for containers that don't belong to the node have `k8s_pod_name=<NA>`. Filter by pod or namespace.
- The kind node itself is a container from the kernel's point of view. Expect `Executing binary not part of base image` alerts for `mount`/`umount` that the kubelet runs (no pod name), whenever a Pod with volumes starts.
- `libpman: disabled BPF iterators (not running in the root PID namespace)` in the log is harmless.
- Falco uses about 100 MB of memory on the worker.

## seccomp: works

The kernel has `CONFIG_SECCOMP=y`. Docker shows `Seccomp: 2` in containers. On the kind nodes, `RuntimeDefault` (containerd's default profile) and `Localhost` profiles from `/var/lib/kubelet/seccomp/` work. Blocked syscalls fail with `Operation not permitted` (item `seccomp-profile`).

## gVisor: works

`runsc` from the gVisor apt repository runs inside a kind node on WSL2 without extra flags (default `systrap` platform). `init-cluster.sh` adds this to the worker's `/etc/containerd/config.toml` and restarts containerd:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
```

With a `RuntimeClass` whose `handler: runsc`, Pods start in the sandbox: `dmesg` prints `Starting gVisor...`, and `uname -r` shows `4.19.0-gvisor`. Cluster DNS, Service IPs and outbound internet work from inside the sandbox (verified with busybox `nslookup` and `wget`). Only the worker has `runsc`. The control plane is tainted, so Pods land on the worker anyway (item `gvisor-runtimeclass`).

## AppArmor: needs setup (untested)

**Current state (verified):** the WSL2 kernel is built with `CONFIG_SECURITY_APPARMOR=y`, but its `CONFIG_LSM` list starts with SELinux and the default boot command line selects no LSM. So AppArmor is not active:

```bash
cat /sys/module/apparmor/parameters/enabled       # N
docker run --rm --privileged alpine sh -c \
  'mount -t securityfs securityfs /sys/kernel/security; cat /sys/kernel/security/lsm'
# capability,landlock,yama,safesetid,selinux        <- no apparmor
```

On the kind nodes, `apparmor_parser` then fails, and the kubelet rejects Pods with an AppArmor profile: `Cannot enforce AppArmor: AppArmor is not enabled on the host`. The `apparmor-profile` item checks for this in its setup and stops with a pointer to this page. It is practice-only, so mock exams never draw it.

**How to enable it. These steps are untested, and they change the WSL VM for all distributions:**

1. In the WSL distribution, install the AppArmor userspace tools first: `sudo apt-get install -y apparmor`. Once AppArmor is active, Docker loads its `docker-default` profile for every non-privileged container with `apparmor_parser`. Without the tools, containers fail to start with "AppArmor enabled on system but the docker-default profile could not be loaded".
2. In Windows, edit `%UserProfile%\.wslconfig` (create the file if it doesn't exist):
   ```ini
   [wsl2]
   kernelCommandLine = lsm=landlock,lockdown,yama,integrity,apparmor
   ```
   `lsm=` replaces the kernel's built-in list. This is the list Ubuntu's own kernels use: AppArmor instead of SELinux, which WSL doesn't use. The shorter `kernelCommandLine = apparmor=1 security=apparmor`, common in guides, should have the same effect (`security=` picks the major LSM). If `.wslconfig` already has a `kernelCommandLine`, append to it.
3. Restart WSL from PowerShell or cmd: `wsl --shutdown`, then open the distribution again. This stops all distributions and Docker. Afterwards, start or recreate the kind clusters: `./scripts/init-cluster.sh --profile cks --recreate`.
4. Verify:
   ```bash
   cat /proc/cmdline                                  # contains lsm=...apparmor
   cat /sys/module/apparmor/parameters/enabled       # Y
   sudo aa-status | head -3                           # "apparmor module is loaded."
   docker info | grep -A3 'Security Options'          # lists apparmor
   docker exec cka-cks-worker cat /sys/module/apparmor/parameters/enabled   # Y on the kind node too
   ```
   Then run `./scripts/lab.sh setup apparmor-profile`. It mounts securityfs in the node if it's missing, and restarts containerd and the kubelet so that they detect AppArmor.

To undo it, remove the line from `.wslconfig` and run `wsl --shutdown` again.

The kind nodes run as privileged containers, so Docker runs them unconfined. Profiles loaded on a node with `apparmor_parser` go into the shared kernel, so they are visible to every node and to the host. They are lost on `wsl --shutdown`.

## Not covered

- **Pod-to-pod encryption** (Cilium WireGuard/IPsec, Istio/Linkerd mTLS): not part of the cks profile. Cilium would need a cluster without kindnet (`disableDefaultCNI`) and would add several minutes and about 1 GB of images to every cks cluster. A service mesh is similar or bigger. Both are possible on kind, but cost too much for one curriculum bullet.
- **Host-level changes** (kernel modules, sysctls of the real host): the nodes share your kernel, so a task that changes kernel state would change your WSL VM. The node items only change files and services inside the node containers.
