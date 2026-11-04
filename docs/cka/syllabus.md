# CKA Syllabus

The five domains of the CKA curriculum with the concepts, commands and manifests for each.

---

## CKA Syllabus Breakdown (v1.37)

The domain weights below match the current official CKA curriculum. The Kubernetes version in the exam environment can change; see the version note in the [CKA overview](README.md#exam-details).

### Domain 1 — Storage (10%)

10% of the score. Sounds small, but the questions are straightforward if you understand PV/PVC binding — easy points that are easy to skip in a study plan. The main trap: `storageClassName` has to match exactly between PV and PVC, and "exactly" includes the case where one side has it set and the other doesn't.

> See also: [Storage](../../questions/static-pv-rwx/) | [YAML templates](../templates.md)

#### 1.1 — Understand Storage Classes and Persistent Volumes

Storage on Kubernetes is simple in concept but annoying in practice. A **PV** is the actual storage (think: the hard drive). A **PVC** is a request for that storage (think: "I need 2Gi of disk"). A **StorageClass** tells Kubernetes how to dynamically create PVs when a PVC asks for one.

What actually matters for the exam:
- PV is cluster-scoped (no namespace). PVC is namespace-scoped. A PVC in the wrong namespace binds fine, but the pod can't see it.
- PVC binds to a PV when: capacity >= request, accessModes match, AND storageClassName matches. If any one of these is off, the PVC sits in `Pending` forever with no helpful error message.
- The `storageClassName` trap is real. `manual` ≠ `Manual` ≠ empty string. Triple-check it.

```yaml
# PV — cluster-scoped
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /data/my-pv
```

```yaml
# PVC — namespace-scoped
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: manual
```

```yaml
# Pod using PVC
apiVersion: v1
kind: Pod
metadata:
  name: storage-pod
spec:
  containers:
  - name: app
    image: nginx:1.27
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

#### 1.2 — Understand Volume Mode, Access Modes, and Reclaim Policies

**Access Modes** — you need to know the four-letter abbreviations:

| Mode | Short | What it actually means |
|---|---|---|
| ReadWriteOnce | RWO | One node can mount read-write. This is what you'll use 90% of the time. |
| ReadOnlyMany | ROX | Many nodes can mount read-only. Rarely comes up on the exam. |
| ReadWriteMany | RWX | Many nodes can mount read-write. Doesn't work with hostPath. |
| ReadWriteOncePod | RWOP | Only one pod can mount read-write. New in v1.29+, might show up. |

> CKA-safe rule: `ReadWriteOnce` is node-scoped, not pod-scoped. `ReadWriteOncePod` is the pod-scoped mode. In real clusters, multiple pods on the same node can often use the same `RWO` volume; `RWOP` is the one that enforces a single pod.

**Reclaim Policies** — know the difference or you'll lose data:

| Policy | What actually happens |
|---|---|
| Retain | PV survives PVC deletion. Data is safe but you have to manually clean up the PV before it can be reused. |
| Delete | PV and the underlying storage get nuked. This is the default for most cloud StorageClasses. Be careful. |
| Recycle | Deprecated. Don't use it, don't memorize it. |

**Volume Modes:**
- `Filesystem` (default) — mounted as a directory
- `Block` — raw block device, no filesystem

On the exam: know the difference between Retain and Delete. If the question says "data should persist after PVC deletion," use Retain.

#### 1.3 — Configure Applications with Persistent Storage

The pattern is always the same:
1. Create PV (or let StorageClass provision it dynamically)
2. Create PVC referencing the StorageClass
3. Mount PVC in the Pod spec

```yaml
# StorageClass for dynamic provisioning
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

`WaitForFirstConsumer` delays binding until a pod actually needs the volume. This avoids scheduling issues where the PV is on node A but the pod lands on node B.

Common gotcha: forgetting `storageClassName`. If the PVC has `storageClassName: ""` (empty string), it only binds to PVs with no StorageClass. If you set `storageClassName: manual`, the PV must also have `storageClassName: manual`.

---

### Domain 2 — Troubleshooting (30%)

This is the biggest domain — 30% of the score. You'll get several questions asking you to fix broken things. Without a system, it is easy to lose time checking pods, then nodes, then pods again. A consistent troubleshooting order (nodes → kubelet → control plane pods → describe → logs → endpoints) makes you much faster and more accurate.

> See also: [Troubleshoot Cluster](../../questions/cluster-multi-fault/) | [Troubleshooting Decision Flowchart](troubleshooting.md#troubleshooting-decision-flowchart)

#### 2.1 — Evaluate Cluster and Node Logging

Where to find logs:

| Component | Log Location |
|---|---|
| kubelet | `journalctl -u kubelet` (systemd service) |
| kube-apiserver | `/var/log/kube-apiserver.log` or `k logs -n kube-system kube-apiserver-<node>` |
| kube-scheduler | `k logs -n kube-system kube-scheduler-<node>` |
| kube-controller-manager | `k logs -n kube-system kube-controller-manager-<node>` |
| etcd | `k logs -n kube-system etcd-<node>` |
| Container runtime | `journalctl -u containerd` |

Control plane components run as static pods (in `/etc/kubernetes/manifests/`), so you can check their logs with `k logs`. But kubelet is a systemd service — use `journalctl`.

```bash
# Check node status
k get nodes
k describe node <node-name>

# Check kubelet on a node
ssh <node>
sudo systemctl status kubelet
sudo journalctl -u kubelet --no-pager | tail -50

# Check control plane pods
k get pods -n kube-system
```

#### 2.2 — Monitor Applications

Honestly, monitoring during the exam boils down to two things: `k describe` and `k get events`. `k top` needs metrics-server, which isn't available on every cluster — but know it exists in case a task asks for it.

```bash
# These two are 90% of exam monitoring
k describe pod <pod-name>       # events section at bottom tells you everything
k get events --sort-by='.lastTimestamp'

# The rest — know them, probably won't need them
k get pods
k top pods
k top nodes
k get events -n <namespace> --field-selector reason=Failed
```

#### 2.3 — Container stdout/stderr Logs

The two you'll actually use on the exam: `k logs <pod>` and `k logs <pod> --previous`. The rest are nice-to-know; `-f` and `--tail` rarely matter under exam time pressure.

```bash
# The essentials
k logs <pod-name>
k logs <pod-name> --previous                 # crashed container — you'll use this a lot
k logs <pod-name> -c <container-name>         # multi-container pods

# Rarely needed on the exam but useful
k logs <pod-name> -f
k logs <pod-name> --tail=50
k logs -l app=web --all-containers
```

#### 2.4 — Troubleshoot Application Failure

The exam gives you a broken pod and you figure out why. After enough practice, you develop a reflex based on the status:

**Pending** — this is the most common one on the exam. 9 times out of 10 it's one of these:
- PVC not bound → `k get pvc` — check storageClassName matches
- Taint with no toleration → `k describe node` and look at Taints
- No resources available → `k describe pod` events will say "Insufficient cpu"
- Node selector or affinity doesn't match any node → check labels
- A Pending pod can simply need a namespace ResourceQuota increased — check quotas early

**CrashLoopBackOff** — the container starts and dies immediately:
- `k logs <pod> --previous` first. Always. The error is usually obvious.
- Wrong command/entrypoint is the sneaky one — `["sh", "-c"]` vs `["sh -c"]` is easy to miss
- Missing config (env vars, configmaps, secrets)

**ImagePullBackOff** — almost always a typo in the image name. Seriously. Check the image string character by character.
- Private registry without imagePullSecrets is the other cause, but rare on the exam

**Error / Failed:**
- `k describe pod` events section → `k logs` → you'll find it

```bash
# Systematic pod debugging
k get pod <pod> -o wide          # which node? what IP?
k describe pod <pod>             # events, conditions
k logs <pod>                     # app logs
k logs <pod> --previous          # if it crashed
k exec <pod> -- cat /etc/resolv.conf   # DNS config
k exec <pod> -- env                     # env vars loaded?
```

#### 2.5 — Troubleshoot Cluster Component Failure

When the whole cluster is broken:

```bash
# 1. Are nodes ready?
k get nodes

# 2. Are control plane pods running?
k get pods -n kube-system

# 3. Is kubelet running on the node?
ssh <node>
sudo systemctl status kubelet
sudo systemctl restart kubelet    # try restarting

# 4. Check kubelet logs
sudo journalctl -u kubelet --no-pager | tail -50

# 5. Are certificates expired?
sudo kubeadm certs check-expiration

# 6. Is etcd healthy?
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 7. Check static pod manifests
ls /etc/kubernetes/manifests/
# Should have: etcd.yaml, kube-apiserver.yaml, kube-controller-manager.yaml, kube-scheduler.yaml
```

Common causes:
- kubelet not running → `systemctl start kubelet`
- Wrong static pod manifest → fix YAML in `/etc/kubernetes/manifests/`
- Certificates expired → `kubeadm certs renew all`
- etcd data directory wrong → check `--data-dir` in etcd manifest
- kube-apiserver flag wrong → check manifest, fix, wait for restart

#### 2.6 — Troubleshoot Networking

Service not reachable? Work through this:

```bash
# 1. Does the service exist and have the right selector?
k get svc <service>
k describe svc <service>

# 2. Does the service have endpoints?
k get endpoints <service>
# If empty: selector doesn't match any running pod

# 3. Is the pod actually running on the target port?
k exec <pod> -- wget -qO- localhost:<port>

# 4. DNS working?
k run test-dns --image=busybox:1.36 --rm -it -- nslookup <service-name>

# 5. Is kube-proxy running?
k get pods -n kube-system -l k8s-app=kube-proxy

# 6. NetworkPolicy blocking traffic?
k get networkpolicy -n <namespace>
```

The most common networking issues on the exam:
- Service selector doesn't match pod labels (typo in labels)
- Service targetPort doesn't match container port
- NetworkPolicy denying traffic (remember: any policy = deny by default for that pod)
- CoreDNS down or misconfigured
- kube-proxy not running on a node

---

### Domain 3 — Workloads & Scheduling (15%)

15% of the score. Deployments, rolling updates, ConfigMaps, Secrets, static pods, scheduling constraints. For most people the most comfortable domain, because it's what you do day-to-day. The gotcha: static pods. Deleting them with kubectl just brings them back. Once you understand the kubelet manages them directly, it clicks.

> See also: [Pod Basics](../../questions/pod-labels-resources/) | [Deployment Rollout](../../questions/rollout-rollback/) | [Static Pod](../../questions/static-pod/)

#### 3.1 — Understand Deployments and How to Perform Rolling Updates and Rollbacks

Deployments manage ReplicaSets, which manage Pods. When you update the image, Kubernetes creates a new ReplicaSet and gradually shifts pods over. A common trap: the container name in `k set image` is the container name from the pod spec, not the deployment name. `k set image deployment/webapp webapp=nginx:1.27` fails when the container is actually called `nginx`.

```bash
# Create
k create deployment webapp --image=nginx:1.26 --replicas=3

# Update image (triggers rolling update)
k set image deployment/webapp nginx=nginx:1.27

# Watch the rollout
k rollout status deployment/webapp

# Check history
k rollout history deployment/webapp

# Rollback to previous
k rollout undo deployment/webapp

# Rollback to specific revision
k rollout undo deployment/webapp --to-revision=2
```

Rolling update strategy options:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # max pods above desired count during update
      maxUnavailable: 0   # max pods that can be unavailable during update
```

- `maxSurge: 1, maxUnavailable: 0` = zero-downtime (one extra pod at a time)
- `maxSurge: 0, maxUnavailable: 1` = no extra pods, one goes down at a time
- `Recreate` strategy = kill all old pods first, then create new ones (causes downtime)

#### 3.2 — Use ConfigMaps and Secrets to Configure Applications

ConfigMaps hold non-sensitive config. Secrets hold sensitive data (base64-encoded, not encrypted by default).

```bash
# Create ConfigMap
k create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=info

# Create Secret
k create secret generic db-creds \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASS=changeme

# From file
k create configmap nginx-conf --from-file=nginx.conf
```

Three ways to inject into a pod:

**1. Environment variables (all keys):**
```yaml
envFrom:
- configMapRef:
    name: app-config
- secretRef:
    name: db-creds
```

**2. Single key as env var:**
```yaml
env:
- name: DATABASE_USER
  valueFrom:
    secretKeyRef:
      name: db-creds
      key: DB_USER
```

**3. Mounted as files:**
```yaml
volumeMounts:
- name: config-vol
  mountPath: /etc/config
volumes:
- name: config-vol
  configMap:
    name: app-config
```

Gotcha: if you mount a ConfigMap as a volume at a directory, it replaces the entire directory. Use `subPath` to mount a single file without replacing the directory.

#### 3.3 — Know How to Scale Applications

```bash
# Manual scaling
k scale deployment webapp --replicas=5

# Autoscaling (HPA — not heavily tested on CKA but know it exists)
k autoscale deployment webapp --min=2 --max=10 --cpu-percent=80
```

#### 3.4 — Self-Healing Workloads: Deployments, DaemonSets, StatefulSets

The one you'll actually use on the exam is **Deployment**. It manages ReplicaSets, which manage Pods. You create Deployments, you scale them, you update them, you roll them back. That's 90% of this topic.

- **ReplicaSet**: Keeps N pods running. You almost never create these directly — Deployments create them for you.
- **Deployment**: This is the workhorse. Rolling updates, rollbacks, scaling. Know this cold.
- **DaemonSet**: One pod per node. Logging agents, monitoring. Comes up occasionally on the exam. The YAML is basically a Deployment without `replicas`.
- **StatefulSet**: Stable network identity and persistent storage. Barely on the CKA — know it exists, maybe know the headless service pattern, don't spend hours on it.

```yaml
# DaemonSet — runs on every node
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: fluentd:v1.17
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

#### 3.5 — Understand How Resource Limits Can Affect Pod Scheduling

```yaml
resources:
  requests:
    memory: "64Mi"    # scheduler uses this to find a node
    cpu: "250m"       # 250 millicores = 0.25 CPU
  limits:
    memory: "128Mi"   # OOMKilled if exceeded
    cpu: "500m"       # throttled if exceeded
```

- **Requests** = what the scheduler looks at when placing the pod. If no node has enough, pod stays Pending.
- **Limits** = ceiling. Memory over limit = OOMKilled. CPU over limit = throttled.
- If you set limits without requests, requests default to limits.
- LimitRange sets defaults and constraints for a namespace. ResourceQuota caps total usage.

#### 3.6 — Awareness of Manifest Management and Common Templating Tools

On the CKA, you mostly write raw YAML. But know these exist:
- **Kustomize**: `k apply -k <dir>` — built into kubectl, overlays and patches
- **Helm**: package manager for Kubernetes — CKA may ask you to install a chart
- **kubectl $do**: generate YAML with `--dry-run=client -o yaml` and edit it

#### 3.7 — Schedule Pods on Specific Nodes

**nodeSelector** (simplest):
```yaml
spec:
  nodeSelector:
    disk: ssd
```

**Node affinity** (more flexible):
```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disk
            operator: In
            values:
            - ssd
```

**Taints and tolerations:**

Taints go on nodes. Tolerations go on pods.

```bash
# Taint a node
k taint nodes node1 gpu=true:NoSchedule

# Remove taint
k taint nodes node1 gpu=true:NoSchedule-
```

```yaml
# Pod toleration
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

Effects:
- `NoSchedule` — don't schedule new pods (existing stay)
- `PreferNoSchedule` — try to avoid, but not strict
- `NoExecute` — evict existing pods too

#### 3.8 — Static Pods

Static pods are managed by the kubelet directly, not the API server. The kubelet watches a directory (usually `/etc/kubernetes/manifests/`) and creates pods from any YAML files it finds there.

```bash
# Find the static pod path
cat /var/lib/kubelet/config.yaml | grep staticPodPath
# Usually: /etc/kubernetes/manifests

# Create a static pod
sudo tee /etc/kubernetes/manifests/static-web.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: static-web
spec:
  containers:
  - name: web
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
```

Static pods show up in `kubectl get pods` with the node name appended (e.g., `static-web-node1`). You can't delete them via kubectl — the kubelet recreates them. To remove: delete the manifest file.

Control plane components (kube-apiserver, kube-scheduler, kube-controller-manager, etcd) are all static pods.

---

### Domain 4 — Cluster Architecture, Installation & Configuration (25%)

25% of the score. This is the domain that separates CKA from CKAD — etcd, kubeadm, RBAC. If you're coming from CKAD, this is all new and deserves the most study time. etcd backup/restore takes a while to get reliable, and the `--as=system:serviceaccount:ns:name` syntax for testing RBAC needs drilling until it is automatic.

> See also: [RBAC](../../questions/rbac-user-and-serviceaccount/) | [kubeadm Upgrade](../../questions/kubeadm-upgrade/) | [CRI-dockerd Setup](../../questions/cri-dockerd-setup/)

#### 4.1 — Manage Role-Based Access Control (RBAC)

RBAC has four objects:

| Object | Scope | Binds to |
|---|---|---|
| Role | Namespace | RoleBinding |
| ClusterRole | Cluster-wide | ClusterRoleBinding or RoleBinding |
| RoleBinding | Namespace | Role or ClusterRole |
| ClusterRoleBinding | Cluster-wide | ClusterRole |

```bash
# Create Role (namespace-scoped permissions)
k create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  -n dev

# Create RoleBinding
k create rolebinding read-pods \
  --role=pod-reader \
  --serviceaccount=dev:my-sa \
  -n dev

# Create ClusterRole (cluster-wide permissions)
k create clusterrole node-reader \
  --verb=get,list \
  --resource=nodes

# Create ClusterRoleBinding
k create clusterrolebinding read-nodes \
  --clusterrole=node-reader \
  --serviceaccount=dev:my-sa

# Test permissions
k auth can-i list pods -n dev --as=system:serviceaccount:dev:my-sa
k auth can-i list nodes --as=system:serviceaccount:dev:my-sa
```

Tricky bit: a ClusterRole bound with a RoleBinding only grants access in that namespace. A ClusterRole bound with a ClusterRoleBinding grants access cluster-wide. Same ClusterRole, different scope depending on the binding type.

#### 4.2 — Use Kubeadm to Install a Basic Cluster

The kubeadm workflow:

```bash
# On control plane node:
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (e.g., Calico)
k apply -f https://docs.projectcalico.org/manifests/calico.yaml

# On worker nodes:
sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

If you lost the join command:
```bash
kubeadm token create --print-join-command
```

#### 4.3 — Manage a Highly Available Kubernetes Cluster

You won't set up HA from scratch on the exam, but they want you to understand the two topologies:

- **Stacked etcd**: etcd on the same nodes as the control plane. This is what everyone uses. Simpler, good enough for most setups.
- **External etcd**: etcd on dedicated nodes. Rarely set up by hand; just know it exists and that it's "more resilient" because etcd failures don't take down the control plane node.
- Multiple control plane nodes behind a load balancer — the LB endpoint goes in `kubeadm init --control-plane-endpoint=<lb>:6443`

About 10 minutes on this topic is enough: read it, understand the difference, move on.

#### 4.4 — Provision Underlying Infrastructure to Deploy a Kubernetes Cluster

kubeadm handles most of this. You won't provision VMs on the exam, but you might need to fix a node that was set up wrong. The things that break:
- containerd not installed or not running — `systemctl status containerd`
- Swap still enabled — `swapoff -a` (easy to forget on fresh VMs)
- Missing kernel modules: `br_netfilter` and `overlay`. Load them with `modprobe`.
- sysctl params — `net.bridge.bridge-nf-call-iptables = 1`. Nobody remembers the exact name; grep the docs page.

#### 4.5 — Perform a Version Upgrade on a Kubernetes Cluster Using Kubeadm

This is a classic CKA question. The sequence matters:

**Control plane node:**
```bash
# 1. Update kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm

# 2. Plan
sudo kubeadm upgrade plan

# 3. Apply
sudo kubeadm upgrade apply v1.35.0

# 4. Update kubelet + kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl

# 5. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**Worker node:**
```bash
# 1. From control plane: drain the worker
k drain worker-1 --ignore-daemonsets --delete-emptydir-data

# 2. SSH to worker, update packages
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update
sudo apt-get install -y kubeadm=1.35.0-1.1 kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl

# 3. Upgrade node
sudo kubeadm upgrade node

# 4. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. From control plane: uncordon
k uncordon worker-1
```

Key difference: control plane uses `kubeadm upgrade apply`, worker uses `kubeadm upgrade node`.

#### 4.6 — Implement etcd Backup and Restore

etcd backup and restore are part of cluster administration. Practice the commands and confirm the restored data rather than relying on memorized flags alone.

**Backup:**
```bash
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Where to find the cert paths: `cat /etc/kubernetes/manifests/etcd.yaml` and look for `--cert-file`, `--key-file`, `--trusted-ca-file`.

**Verify:**
```bash
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-table
```

**Restore:**
```bash
# 1. Restore to a new directory
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored

# 2. Update etcd manifest to use the restored directory
sudo vi /etc/kubernetes/manifests/etcd.yaml
# Change --data-dir=/var/lib/etcd → --data-dir=/var/lib/etcd-restored
# Change hostPath path: /var/lib/etcd → /var/lib/etcd-restored

# 3. Wait for etcd to restart (it's a static pod)
# kubectl may be unresponsive for 30-60 seconds — that's normal
```

The three flags you need every time: `--cacert`, `--cert`, `--key`. Write them on the notepad in the exam environment before starting.

---

### Domain 5 — Services & Networking (20%)

20% of the score. Services, Ingress, Gateway API, NetworkPolicy, DNS. NetworkPolicy is where most points get lost — the AND vs OR selector behavior is unintuitive, and forgetting DNS egress is a silent killer.

> See also: [NetworkPolicy](../../questions/netpol-three-tier/) | [YAML templates](../templates.md)

#### 5.1 — Understand Host Networking Configuration on the Cluster Nodes

Networking in Kubernetes "just works" if your CNI is installed correctly. Don't overthink the model — pods get IPs, pods can talk to each other, nodes can talk to pods. The CNI plugin (Calico, Flannel, Cilium) makes it happen. That's really all you need to know conceptually.

What actually matters for the exam: knowing where to look when it doesn't work.

```bash
# Check what CNI is installed
ls /etc/cni/net.d/
cat /etc/cni/net.d/10-calico.conflist

# Check pod CIDR
k cluster-info dump | grep -m 1 cluster-cidr
```

#### 5.2 — Understand Connectivity Between Pods

Same-node pods talk through a bridge, cross-node pods go through the CNI overlay. You don't need to know the internals — but you need to test connectivity when something breaks.

```bash
# Test pod-to-pod connectivity
k exec pod-a -- wget -qO- --timeout=2 http://<pod-b-ip>

# Check pod IPs
k get pods -o wide
```

#### 5.3 — Understand ClusterIP, NodePort, LoadBalancer Service Types

| Type | How it works | When to use |
|---|---|---|
| **ClusterIP** | Internal cluster IP only | Internal services (default) |
| **NodePort** | ClusterIP + port on every node (30000-32767) | Dev/testing, direct node access |
| **LoadBalancer** | NodePort + cloud LB | Production with cloud provider |
| **ExternalName** | CNAME to external DNS | Pointing to external services |

```bash
# ClusterIP (default)
k expose deployment webapp --port=80 --target-port=8080

# NodePort (random port in 30000-32767)
k expose deployment webapp --port=80 --target-port=8080 --type=NodePort

# Specific NodePort — generate YAML, edit nodePort, then apply
k expose deployment webapp --port=80 --target-port=8080 --type=NodePort $do > svc.yaml
# edit svc.yaml → set spec.ports[0].nodePort: 30080
k apply -f svc.yaml
```

The most important thing: `port` is what clients use to reach the service. `targetPort` is the port the container listens on. `nodePort` is the port on the node (NodePort/LoadBalancer only).

#### 5.4 — Understand How to Use Ingress Controllers and Ingress Resources

Ingress gives you HTTP/HTTPS routing to services based on hostname or path.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

Requirements:
- An Ingress Controller must be installed (e.g., nginx-ingress). The Ingress resource alone does nothing.
- `ingressClassName` is required in v1.35 — the old annotation `kubernetes.io/ingress.class` still works but is deprecated.

#### 5.5 — Know How to Use and Configure CoreDNS

CoreDNS is the cluster DNS server (replaced kube-dns a long time ago). It runs as a Deployment in `kube-system`.

```bash
# Check CoreDNS pods
k get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS config
k get configmap coredns -n kube-system -o yaml

# Test DNS resolution
k run test-dns --image=busybox:1.36 --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

DNS naming:
- Service: `<service>.<namespace>.svc.cluster.local`
- Pod: `<pod-ip-dashed>.<namespace>.pod.cluster.local`

If DNS doesn't work:
1. Is CoreDNS running? `k get pods -n kube-system -l k8s-app=kube-dns`
2. Does kube-dns service have endpoints? `k get endpoints kube-dns -n kube-system`
3. Is the Corefile correct? `k get cm coredns -n kube-system -o yaml`
4. Can the pod reach the DNS service? `k exec <pod> -- cat /etc/resolv.conf`

#### 5.6 — Choose an Appropriate Container Network Interface Plugin

The CKA won't ask you to write a CNI plugin. Just use Calico. It supports NetworkPolicy, it's the most common, and it's what most training platforms use. The exam doesn't care which CNI is installed.

Other CNIs exist — Flannel is simpler but doesn't support NetworkPolicy (dealbreaker for the exam), Cilium is the fancy eBPF one everyone's talking about, Weave still works. But if a question says "install a CNI plugin," just apply the Calico manifest and move on.

Install is one `kubectl apply -f <url>`. The CNI must be installed before worker nodes join — pods stay Pending without it.

#### 5.7 — Understand NetworkPolicy

NetworkPolicy controls pod-to-pod traffic. Once you apply any NetworkPolicy to a pod, all traffic not explicitly allowed is denied for that pod.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  # Always allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
```

Critical gotcha on the exam: if you add an Egress policy, you must also allow DNS (UDP 53). Otherwise the pod can't resolve any service names and everything looks broken even though the policy is "correct."

Another gotcha: `from` with multiple selectors in one rule = AND. Multiple rules = OR.

```yaml
# AND — must match BOTH namespace AND pod label
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: prod
    podSelector:
      matchLabels:
        app: frontend

# OR — matches namespace OR pod label
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: prod
- from:
  - podSelector:
      matchLabels:
        app: frontend
```

This difference trips up a lot of people. Read the indentation carefully.

#### 5.8 — Gateway API

Gateway API provides resources for configuring service traffic. Which resources work depends on the Gateway API version and controller installed in the cluster. The current CKA curriculum includes Gateway API; consult that curriculum and the relevant controller documentation for scope and setup.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
spec:
  parentRefs:
  - name: my-gateway
  hostnames:
  - "myapp.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-service
      port: 80
```

Key differences from Ingress:
- Gateway = infrastructure resource (managed by platform team)
- HTTPRoute = application routing (managed by app team)
- More features: header matching, traffic splitting, request mirroring
- Supports TCP, UDP, gRPC — not just HTTP
