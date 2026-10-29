# Tune the kubelet configuration

**Context:** `kubectl config use-context {{CONTEXT}}`

Node `{{NODE_W1}}` (`ssh {{NODE_W1}}`) needs a different kubelet configuration. Change it on this node only:

1. The node must accept at most `{{MAX_PODS}}` pods.
2. Add a hard eviction threshold: evict pods when the available memory drops below `{{MEM_EVICT}}`. Keep the hard eviction thresholds that are already configured.
3. The running kubelet must use the new settings, and the node must be `Ready`.

## Hints

- kubeadm-based nodes read the kubelet settings from the KubeletConfiguration file passed with `--config` (see `systemctl cat kubelet`).
- The fields are `maxPods` and `evictionHard` (a map of signal to threshold, for example `memory.available`). Field names are case-sensitive.
- The kubelet reads its config file only at startup: `systemctl restart kubelet`. `k get node {{NODE_W1}} -o jsonpath='{.status.allocatable.pods}'` and `k get --raw /api/v1/nodes/{{NODE_W1}}/proxy/configz` show what the running kubelet uses.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_W1}}
systemctl cat kubelet | grep -- --config      # --config=/var/lib/kubelet/config.yaml
vim /var/lib/kubelet/config.yaml
```

```yaml
evictionHard:
  imagefs.available: 0%
  nodefs.available: 0%
  nodefs.inodesFree: 0%
  memory.available: {{MEM_EVICT}}
maxPods: {{MAX_PODS}}
```

```bash
systemctl restart kubelet
systemctl status kubelet                      # active (running)
exit

k get node {{NODE_W1}} -o jsonpath='{.status.allocatable.pods}{"\n"}'    # {{MAX_PODS}}
k get --raw /api/v1/nodes/{{NODE_W1}}/proxy/configz | grep -o '"evictionHard":{[^}]*}'
```

`maxPods` doesn't exist in the file yet, so add it as a top-level key. `evictionHard` is a map: add the new signal next to the existing ones. If you replace the whole map, the other thresholds are dropped (check `configz`). The node's allocatable pods show that the restart picked up the change. This file is local to the node. `kubeadm upgrade node` rewrites it from the cluster-wide `kubelet-config` ConfigMap in `kube-system`, so a permanent cluster-wide change belongs there.
