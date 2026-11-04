# Size resource requests to fit a node

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `web` in namespace `capacity` (3 replicas, `nginx:1.27`, pinned to node `{{NODE_W1}}` with a `nodeSelector`) requests so much CPU and memory per replica that only one replica can run; the others stay Pending.

1. Scale `web` down to 0 and find out how much CPU and memory is still free on `{{NODE_W1}}` (Allocatable minus what the other pods on the node already request).
2. Divide the free CPU and memory evenly across 3 replicas, keeping a buffer of 5-10%, and set these values as the requests of `web`. Keep the image and the `nodeSelector`.
3. Scale `web` back to 3 replicas. All 3 must be Running.

The values are checked against the node: each replica must request between 75% and 100% of a third of the free CPU and memory.

## Hints

- `k describe pod <pending-pod>` shows why it can't be scheduled (`Insufficient cpu`, `Insufficient memory`).
- `k describe node {{NODE_W1}}` lists `Allocatable` and, further down, `Allocated resources`.
- Scale to 0 first: the running replica would otherwise count towards "Allocated resources".
- Allocatable memory is shown in `Ki` (divide by 1024 for `Mi`); `16` CPUs are `16000m`.
- `k set resources deploy web --requests=cpu=...,memory=...` changes requests without editing YAML.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n capacity get pods -o wide              # 1 Running, 2 Pending
k -n capacity describe pod <pending-pod>    # 0/3 nodes are available: ... Insufficient cpu, Insufficient memory

k -n capacity scale deploy web --replicas=0
k describe node {{NODE_W1}}
# Allocatable:
#   cpu:     16
#   memory:  30628020Ki
# Allocated resources:
#   cpu      100m
#   memory   50Mi
```

Calculation (numbers from the output above; yours depend on your machine):

```
free CPU     = 16000m - 100m                          = 15900m
free memory  = 30628020Ki / 1024 - 50Mi ≈ 29910Mi - 50Mi = 29860Mi
per replica  = free / 3                               = 5300m CPU, 9953Mi memory
10% buffer   -> requests                              = 4770m CPU, 8958Mi memory
```

```bash
k -n capacity set resources deploy web --requests=cpu=4770m,memory=8958Mi
k -n capacity scale deploy web --replicas=3
k -n capacity get pods -o wide              # 3 Running on {{NODE_W1}}
```

## Pitfalls

- Fixed rules like "reserve 10% per node" don't work: check the node's real Allocatable and what is already allocated, then divide.
- Requests are a scheduling promise, not usage: a pod requesting 512Mi never lands on a node with 256Mi unallocated, even if it only uses 10Mi.
