# CKA Cheat Sheet — One-Page Reference

Print this or keep it open during practice. Organized by what you'll actually need during the exam.

**Jump to:** [Setup](#setup-first-60-seconds) | [Context](#context-every-question) | [Create Resources](#create-resources-fast) | [RBAC](#rbac) | [Deployments](#deployments) | [Node Ops](#node-operations) | [etcd](#etcd-backup--restore) | [kubeadm Upgrade](#kubeadm-upgrade-control-plane) | [Storage](#storage) | [Services](#services) | [NetworkPolicy](#networkpolicy) | [Troubleshooting](#troubleshooting-sequence) | [Static Pods](#static-pods) | [DNS](#dns) | [Quick Debug](#quick-debug) | [Time Savers](#time-savers)

---

## Setup (First 60 Seconds)

Do this before you touch a single question. I lost marks on my first practice exam because I didn't set up aliases and kept typing `kubectl` in full — cost me at least 5 minutes across the whole exam.

```bash
alias k='kubectl'
alias kn='kubectl config set-context --current --namespace'
export do='--dry-run=client -o yaml'    # this saves you on every create question
export now='--force --grace-period=0'    # instant delete, no waiting 30s
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

```bash
# vim ~/.vimrc
set expandtab tabstop=2 shiftwidth=2 number autoindent
```

---

## Context (EVERY QUESTION)

I cannot stress this enough. I answered two questions on the wrong cluster context during practice. Zero points for both. Now I read the context line first and switch immediately, before reading the rest of the question.

```bash
k config use-context <name>        # Switch context — DO THIS FIRST
k config set-context --current --namespace=<ns>  # Set namespace
k config current-context           # Verify
```

---

## Create Resources Fast

```bash
k run pod1 --image=nginx:1.27 $do > pod.yaml
k create deployment dep1 --image=nginx:1.27 --replicas=3 $do > dep.yaml
k expose deployment dep1 --port=80 --target-port=80 $do > svc.yaml
k create job job1 --image=busybox:1.36 -- sh -c "echo done" $do > job.yaml
k create cronjob cron1 --image=busybox:1.36 --schedule="*/5 * * * *" -- date $do > cron.yaml
k create cm my-cm --from-literal=KEY=value
k create secret generic my-sec --from-literal=PASS=secret
k create sa my-sa -n <ns>
```

---

## RBAC

```bash
k create role <name> --verb=get,list,watch --resource=pods -n <ns>
k create rolebinding <name> --role=<role> --serviceaccount=<ns>:<sa> -n <ns>
k create clusterrole <name> --verb=get,list --resource=nodes
k create clusterrolebinding <name> --clusterrole=<cr> --serviceaccount=<ns>:<sa>
k auth can-i <verb> <resource> -n <ns> --as=system:serviceaccount:<ns>:<sa>
```

---

## Deployments

```bash
k set image deployment/<name> <container>=<image>   # Rolling update
k rollout status deployment/<name>                   # Watch
k rollout history deployment/<name>                  # History
k rollout undo deployment/<name>                     # Rollback
k rollout undo deployment/<name> --to-revision=2     # Specific revision
k scale deployment/<name> --replicas=5               # Scale
```

---

## Node Operations

```bash
k drain <node> --ignore-daemonsets --delete-emptydir-data
k cordon <node>
k uncordon <node>
k taint nodes <node> key=value:NoSchedule
k taint nodes <node> key=value:NoSchedule-          # Remove
k label nodes <node> disk=ssd
```

---

## etcd Backup & Restore

This is almost guaranteed on the exam. I practiced this 10+ times until I could type it from memory. The cert paths are always in the etcd manifest — don't memorize them, grep for them.

```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save /tmp/backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status /tmp/backup.db --write-table

# Restore
ETCDCTL_API=3 etcdctl snapshot restore /tmp/backup.db \
  --data-dir=/var/lib/etcd-restored
# Then update /etc/kubernetes/manifests/etcd.yaml:
#   --data-dir=/var/lib/etcd-restored
#   hostPath.path: /var/lib/etcd-restored
```

---

## kubeadm Upgrade (Control Plane)

Exact sequence matters. I forgot `daemon-reload` once and the kubelet wouldn't start with the new binary. Also: on workers it's `kubeadm upgrade node`, NOT `apply`.

```bash
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.35.0
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
```

Worker: drain first, `kubeadm upgrade node` (not apply), uncordon after.

---

## Storage

```bash
# PV - cluster scoped
# PVC - namespace scoped, must match: storageClassName, accessModes
# Pod: spec.volumes[].persistentVolumeClaim.claimName + volumeMounts
```

Access modes: `ReadWriteOnce (RWO)` | `ReadOnlyMany (ROX)` | `ReadWriteMany (RWX)` | `ReadWriteOncePod (RWOP)`

Reclaim: `Retain` (keep data) | `Delete` (remove PV)

---

## Services

| Type | Scope | Port Range |
|---|---|---|
| ClusterIP | Internal only | Any |
| NodePort | Node IP + port | 30000-32767 |
| LoadBalancer | External LB | Any |

```bash
k expose deployment <name> --port=80 --target-port=8080 --type=NodePort
```

`port` = service port. `targetPort` = container port. `nodePort` = external port.

---

## NetworkPolicy

The DNS egress rule below has saved me more points than any other single piece of YAML. Write it first, every time.

```yaml
# Default deny all ingress
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

Always allow DNS egress when writing egress rules:
```yaml
egress:
- to: []
  ports:
  - protocol: UDP
    port: 53
```

AND vs OR: selectors in the same `from` block = AND. Separate `from` blocks = OR.

---

## Troubleshooting Sequence

This is my exact order. I follow it every time and it's never let me down. The mistake is jumping straight to pod logs — start at the node level and work down.

```bash
k get nodes                              # 1. Nodes ready?
k get pods -n kube-system                # 2. Control plane pods?
ssh <node> -- systemctl status kubelet   # 3. kubelet running?
ssh <node> -- journalctl -u kubelet      # 4. kubelet logs?
k describe pod <pod>                     # 5. Events?
k logs <pod> --previous                  # 6. Previous crash logs?
k get endpoints <svc>                    # 7. Service has endpoints?
k get netpol -A                          # 8. NetworkPolicy blocking?
```

---

## Static Pods

```bash
# Find path
cat /var/lib/kubelet/config.yaml | grep staticPodPath
# Default: /etc/kubernetes/manifests/

# Create: write YAML to that directory
# Delete: remove the file (kubectl delete won't work)
```

---

## DNS

```
<service>.<namespace>.svc.cluster.local
```

```bash
k run test --image=busybox:1.36 --rm -it -- nslookup kubernetes.default
k get pods -n kube-system -l k8s-app=kube-dns           # CoreDNS running?
k get endpoints kube-dns -n kube-system                  # Has endpoints?
```

---

## Quick Debug

```bash
k get events --sort-by=.metadata.creationTimestamp -A    # Cluster events
k top nodes                                              # Node resources
k top pods -A                                            # Pod resources
k get pods -A -o wide                                    # All pods + nodes
k describe node <node> | grep -A5 Conditions             # Node health
k describe node <node> | grep -A10 "Allocated resources" # Node capacity
```

---

## Time Savers

These are the commands that actually saved me time on the exam. The `$do` pattern alone is worth 10+ minutes across the whole test.

- `k explain pod.spec.containers` — YAML field docs in terminal, faster than switching to the browser
- `k get pod -o jsonpath='{.items[*].metadata.name}'` — extract fields
- `k delete pod <name> $now` — instant delete (no grace period)
- `k run tmp --image=busybox:1.36 --rm -it -- sh` — throwaway debug pod
- Copy from docs: kubernetes.io/docs/tasks/ has step-by-step for etcd, kubeadm, RBAC

---

## Patch Objects Fast (Without Rewriting YAML)

When a question asks you to change one field, patching is usually faster and safer than opening a full manifest in vim or nano.

Why patch is useful in exam conditions:
- Updates only the field you target (lower chance of accidental YAML damage)
- Faster than editing a long manifest
- Easy to verify immediately with `jsonpath` or `describe`

Official doc:
- https://kubernetes.io/docs/tasks/manage-kubernetes-objects/update-api-object-kubectl-patch/

I usually copy an example from the official doc first, then change only the field I need (for example, `priorityClassName`). This saves time and avoids patch JSON syntax mistakes.

For image-only updates, `k set image` is usually safer than patching the entire `containers` list.

```bash
# Patch from file (good when patch is reused)
kubectl patch deployment patch-demo --patch-file patch-file.json

# Inline patch (good for one-off changes)
kubectl patch deployment patch-demo --patch '{"spec":{"template":{"spec":{"containers":[{"name":"patch-demo-ctr-2","image":"redis"}]}}}}'

# PriorityClass example
# Create PriorityClass with a practical app value
k create priorityclass high-priority --value=1000 --description="high priority"

# Patch deployment pod template to use it
k patch deployment busybox-logger -n priority -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'

# Verify quickly
k get deploy busybox-logger -n priority -o jsonpath='{.spec.template.spec.priorityClassName}{"\n"}'
k describe deployment busybox-logger -n priority | grep -i "Priority Class"