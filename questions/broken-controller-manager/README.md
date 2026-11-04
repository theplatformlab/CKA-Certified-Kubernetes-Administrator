# Deployment creates no pods

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `invoice-api` in namespace `ledger` was created a while ago, but it still has no pods. `ssh {{NODE_CP}}` gives you access to the control plane node.

Find the cause and fix it so that all replicas of the Deployment are running. Do not modify the Deployment.

## Hints

- There are no pods, but is there a ReplicaSet? `k -n ledger get rs` and `k -n ledger describe deploy invoice-api`. Which component turns a Deployment into a ReplicaSet and pods?
- `k -n kube-system get pods` shows the control plane pods. The logs of a crashing static pod are in `k -n kube-system logs <pod>` or `crictl logs` on the node.
- The kube-controller-manager stops at startup because of a mistyped flag. Compare the flag names in `/etc/kubernetes/manifests/kube-controller-manager.yaml` with `kube-controller-manager --help` or the kubeadm defaults.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n ledger get deploy,rs,pods            # Deployment 0/3, no ReplicaSet at all
k -n kube-system get pods                 # kube-controller-manager in CrashLoopBackOff
k -n kube-system logs kube-controller-manager-{{NODE_CP}} | tail -n 1
# Error: unknown flag: --cluster-signing-keyfile

ssh {{NODE_CP}}
sed -i 's|--cluster-signing-keyfile=|--cluster-signing-key-file=|' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml
watch crictl ps --name kube-controller-manager
exit

k -n ledger get deploy invoice-api        # 3/3
```

The Deployment controller, the ReplicaSet controller and most other controllers run inside kube-controller-manager. When it is down, objects are stored but nothing acts on them: no ReplicaSet, no pods, no events. A pod that is `Pending` without events points at the scheduler instead. Here not even a ReplicaSet exists, which points at the controller manager.
