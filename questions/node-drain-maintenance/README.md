# Node maintenance

**Context:** `kubectl config use-context {{CONTEXT}}`

Node `{{NODE_W2}}` needs maintenance.

1. Make the node unschedulable and evict all workloads from it. Only DaemonSet-managed pods may remain on the node.
2. Deployment `shop-api` in namespace `maintenance` must end up with all 3 replicas Ready on other nodes.
3. The standalone pod `scratch` in namespace `maintenance` stores only temporary data. Losing it is acceptable.

Leave the node unschedulable.

## Hints

- `kubectl drain` cordons the node and evicts its pods in one step.
- Drain refuses three kinds of pods: DaemonSet pods, pods with emptyDir data and pods without a controller. Each has its own flag.
- `--ignore-daemonsets --delete-emptydir-data --force`

## Solution

```bash
k config use-context {{CONTEXT}}
k drain {{NODE_W2}} --ignore-daemonsets --delete-emptydir-data --force

k -n maintenance get pods -o wide            # shop-api pods now on other nodes
k get pods -A -o wide --field-selector spec.nodeName={{NODE_W2}}   # only DaemonSet pods
```

- `--ignore-daemonsets` is needed because DaemonSet pods can't be evicted (kube-proxy, kindnet).
- `--delete-emptydir-data` is needed because `scratch` uses an emptyDir.
- `--force` is needed because `scratch` has no controller, so drain must delete it for good.

Don't uncordon. The question wants the node to stay in maintenance.
