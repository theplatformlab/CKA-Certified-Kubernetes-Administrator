# Find resource-hungry pods with kubectl top

**Context:** `kubectl config use-context {{CONTEXT}}`

The cluster runs metrics-server. Namespace `perf` contains several pods; the batch workers carry the label `app=batch`.

1. Of the pods with label `app=batch` in namespace `perf`, find the one with the highest **CPU** usage and write its name (only the pod name) into `{{WORKDIR}}/cpu-pod.txt`.
2. Of the same pods, find the one with the highest **memory** usage and write its name into `{{WORKDIR}}/mem-pod.txt`.

Pods without the label `app=batch` do not count.

## Hints

- `kubectl top` shows the live CPU and memory usage that metrics-server collects. Fresh pods need about a minute before they show up.
- `kubectl top pod` accepts `-n`, `-l` and `--sort-by=cpu|memory`.
- `k -n perf top pod -l app=batch --sort-by=cpu --no-headers | head -1 | awk '{print $1}'` prints just the top pod's name.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n perf top pod -l app=batch --sort-by=cpu
k -n perf top pod -l app=batch --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > {{WORKDIR}}/cpu-pod.txt
k -n perf top pod -l app=batch --sort-by=memory --no-headers | head -1 | awk '{print $1}' > {{WORKDIR}}/mem-pod.txt
cat {{WORKDIR}}/cpu-pod.txt {{WORKDIR}}/mem-pod.txt     # {{CPU_POD}} and {{MEM_POD}}
```

The trap is the label: `noisy-neighbour` in the same namespace uses more CPU and memory than any batch pod, but it is not labelled `app=batch`. Without `-l` you would write the wrong name. `kubectl top node` works the same way for nodes. If `top` says `metrics not available yet`, wait a minute: metrics-server scrapes the kubelets every 15 seconds and needs a couple of samples per pod.
