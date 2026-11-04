# Pods stuck in Pending

**Context:** `kubectl config use-context {{CONTEXT}}`

The pods of Deployment `rescue` in namespace `default` stay `Pending`.

Find the cause and fix it so that all replicas run. Do not modify the Deployment.

## Hints

- A Pending pod without any scheduling events means no scheduler has looked at it.
- Check the control plane pods in kube-system and the logs of the one that isn't running.
- Static pod manifests live in `/etc/kubernetes/manifests` on the control plane node. Compare the file paths in the manifest with what exists on disk.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n default describe pod -l app=rescue      # no events at all -> nothing is scheduling
k -n kube-system get pods                    # kube-scheduler in CrashLoopBackOff
k -n kube-system logs kube-scheduler-{{NODE_CP}}
# ... stat /etc/kubernetes/scheduler.config: no such file or directory

ssh {{NODE_CP}}
ls /etc/kubernetes/                           # scheduler.conf exists
sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.config|--kubeconfig=/etc/kubernetes/scheduler.conf|' \
  /etc/kubernetes/manifests/kube-scheduler.yaml
exit

k -n kube-system get pods -w
k -n default get pods
```

A Pending pod with no `FailedScheduling` event means no scheduler looked at it at all. Check the scheduler, not the pod.
