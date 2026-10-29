# Exercise 26 — CRI-dockerd Installation and Configuration

> Supplemental implementation practice: installing and configuring CRI-dockerd. See the current [CKA curriculum](https://github.com/cncf/curriculum/blob/master/CKA_Curriculum_v1.37.pdf) for official exam scope.
>
> Related: [README — Cluster Maintenance](../../README.md#domain-7--cluster-maintenance-11)

Switch a running node from containerd to cri-dockerd (Docker Engine) and bring it back to Ready with its pods. This is useful implementation practice for clusters that choose Docker Engine, but the curriculum does not require this specific runtime.

This is the second half of [Exercise 18](../18-cri-dockerd-setup/): 18 installs Docker Engine and cri-dockerd, this one points the kubelet at it. It requires 18's end state as prerequisite — `./scripts/lab.sh setup 26` provides it if you skipped 18.

## Tasks

Use the runtime cluster (`./scripts/init-cluster.sh --profile runtime`) and run `./scripts/lab.sh setup 26` first. Setup brings the worker node `cka-runtime-worker` to the end state of Exercise 18 if you have not done it (Docker Engine + cri-dockerd v0.4.9 running, socket `/run/cri-dockerd.sock`), and creates the Deployment `web` (2 × `nginx:1.28`) and Service `web` in namespace `exercise-26`. Those pods run on `cka-runtime-worker` — the only schedulable node — currently through containerd.

Open a root shell on the node with `docker exec -it cka-runtime-worker bash` — the kind equivalent of `ssh cka-runtime-worker` + `sudo -i` in the exam.

1. On the node, confirm that `docker`, `cri-docker.socket` and `cri-docker.service` are active and that `crictl --runtime-endpoint unix:///run/cri-dockerd.sock version` answers
2. Cordon and drain `cka-runtime-worker` (DaemonSet pods stay)
3. Stop the kubelet and point it at cri-dockerd: set `containerRuntimeEndpoint: unix:///run/cri-dockerd.sock` in `/var/lib/kubelet/config.yaml`
4. Remove the pod sandboxes the kubelet leaves behind in containerd (otherwise a second kube-proxy/kindnet keeps running there)
5. Start the kubelet; `cka-runtime-worker` must become `Ready` and report container runtime `docker://...`
6. Uncordon the node; both `web` pods must be Running on `cka-runtime-worker`, as Docker containers, and Service `web` must answer

Validate with `./scripts/lab.sh check 26`.

## Key Learning

- cri-dockerd is a CRI adapter for Docker
- Kubernetes removed the built-in dockershim in v1.24 — Docker Engine needs cri-dockerd
- The kubelet talks to exactly one CRI endpoint: `containerRuntimeEndpoint` in the kubelet config (`--container-runtime-endpoint` is the deprecated flag form)
- Socket location: `/run/cri-dockerd.sock`
- Changing the runtime does not migrate containers: drain first, the pods are recreated by the new runtime
- `crictl` talks to whatever `/etc/crictl.yaml` or `--runtime-endpoint` says, not automatically to the kubelet's runtime

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Kubelet config file: `systemctl cat kubelet` → `--config=/var/lib/kubelet/config.yaml`
- Current runtime per node: `k get nodes -o wide` (CONTAINER-RUNTIME column)
- `--container-runtime=remote` is gone since v1.27; only the endpoint is configured
- Old sandboxes: `crictl --runtime-endpoint unix:///run/containerd/containerd.sock pods`, remove with `rmp -fa`
- Check socket: `ls -la /run/cri-dockerd.sock`
- Kubelet not coming up: `journalctl -u kubelet -n 50 --no-pager`
- Pods as Docker containers: `docker ps --filter label=io.kubernetes.pod.namespace=exercise-26`

</details>

## What tripped me up

> I installed cri-dockerd but didn't enable IP forwarding. Node stayed NotReady because networking wasn't configured. Then I forgot to load `overlay` and `br_netfilter` modules — pods wouldn't start. Always do the full network setup BEFORE starting the service. Once cri-dockerd is running, kubelet needs a full restart (`systemctl restart kubelet`) to recognize it, not just a reload.

## Verify

```bash
./scripts/lab.sh check 26
```

Manual checks:

```bash
k get nodes -o wide                                   # cka-runtime-worker Ready, docker://26.x
k -n exercise-26 get pods -o wide                     # 2 web pods Running on cka-runtime-worker

# On the node (docker exec -it cka-runtime-worker bash)
grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml
systemctl status cri-docker.service --no-pager
docker ps --filter label=io.kubernetes.pod.namespace=exercise-26
crictl --runtime-endpoint unix:///run/containerd/containerd.sock pods   # empty
```

## Cleanup

```bash
./scripts/lab.sh cleanup 26
```

This deletes the namespace and switches the kubelet back to containerd. Docker and cri-dockerd stay installed (`./scripts/lab.sh cleanup 18` stops them); for a pristine node recreate the cluster with `./scripts/init-cluster.sh --profile runtime --recreate`.

<details>
<summary>Solution</summary>

```bash
# 1. Drain the worker (from your workstation)
k drain cka-runtime-worker --ignore-daemonsets
k -n exercise-26 get pods                    # Pending: no other schedulable node

# 2. Shell into the node (in the exam: ssh + sudo -i)
docker exec -it cka-runtime-worker bash

# 3. Docker + cri-dockerd are up
systemctl is-active docker cri-docker.socket cri-docker.service
crictl --runtime-endpoint unix:///run/cri-dockerd.sock version   # RuntimeName: docker

# 4. Point the kubelet at cri-dockerd
systemctl stop kubelet
grep containerRuntimeEndpoint /var/lib/kubelet/config.yaml       # unix:///run/containerd/containerd.sock
sed -i 's|^containerRuntimeEndpoint:.*|containerRuntimeEndpoint: unix:///run/cri-dockerd.sock|' /var/lib/kubelet/config.yaml

# 5. Remove what the kubelet left behind in containerd
crictl --runtime-endpoint unix:///run/containerd/containerd.sock rmp -fa

# 6. Start the kubelet (full restart, not reload)
systemctl start kubelet
systemctl status kubelet --no-pager

# Optional: make plain `crictl` talk to cri-dockerd from now on
echo 'runtime-endpoint: unix:///run/cri-dockerd.sock' > /etc/crictl.yaml
exit

# 7. Back on your workstation
k get nodes -o wide                          # cka-runtime-worker Ready, CONTAINER-RUNTIME docker://...
k uncordon cka-runtime-worker
k -n exercise-26 rollout status deploy web
k -n exercise-26 get pods -o wide

# 8. The pods are Docker containers now
docker exec cka-runtime-worker docker ps --filter label=io.kubernetes.pod.namespace=exercise-26
```

On a fresh kubeadm node you would not switch afterwards but pass the socket up front: `kubeadm join ... --cri-socket unix:///run/cri-dockerd.sock`.

References:
- https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/change-runtime-containerd/ (the same procedure in the opposite direction)

</details>
