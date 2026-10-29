# Exercise 23 — Resource Requests Tuning (Pods Won't Schedule)

> Related: [Deployment skeleton](../../skeletons/deployment.yaml) | [README — Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Debug and fix a Deployment where pods won't schedule due to insufficient resource requests. Learn to calculate proper requests based on node capacity.

## Tasks

Work in namespace `exercise-23` (`./scripts/lab.sh setup 23` creates it).

The Deployment `web` (3 replicas, `nginx:1.27`, pinned to node `cka-practice-worker` with a `nodeSelector`) requests 60% of that node's allocatable CPU and memory per replica — too much: one replica runs, two stay Pending. (kind nodes report the whole host's CPU and memory, so the numbers are derived from the node rather than fixed.)

1. Observe the Pending pods and find out why they won't schedule
2. Check the capacity of `cka-practice-worker`: Allocatable and Allocated resources
3. Scale `web` to 0 so that "Allocated resources" only shows the other workloads on the node
4. Calculate the requests: divide what is still free on the node (Allocatable − Allocated) evenly across 3 replicas, keeping a buffer of 5-10%
5. Update the CPU and memory requests of `web` (keep the image and the `nodeSelector`) and scale back to 3 replicas
6. Verify all 3 pods schedule and run
7. Document the calculation

Validate with `./scripts/lab.sh check 23`. It recomputes the fair share from the node and accepts per-replica requests between 75% and 100% of a third of the free CPU and memory — "just pick something tiny" does not count.

## Key Learning

The exam trick: **Do NOT use fixed rules like "10% overhead"** — calculate based on actual node allocatable resources and what's already running.

Formula:
```
Per-pod request = (Node Allocatable - System Reserved - Already Running) / Number of Replicas
Add buffer of 5-10%
```

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k get nodes` → see available nodes
- `k describe node <node>` → see Allocatable and Allocated resources
- `k top nodes` → see actual usage
- If pods are Pending: `k describe pod <pod>` → check Events for "Insufficient memory"
- `k set resources deploy web --requests=cpu=...,memory=...` changes requests without editing YAML
- Pending pods of the old ReplicaSet and the running replica both distort "Allocated resources" — that's why you scale to 0 first
- Units: allocatable memory is shown in `Ki`; divide by 1024 for `Mi`. `16` CPU = `16000m`

</details>

## What tripped me up

> I used the standard "reserve 10% per node" rule and pods still didn't schedule. Turns out on the lab cluster, nodes had way more system pods running. I wasted 8 minutes before checking `k describe node` to see actual allocatable vs allocated. The real exam has variable node sizes and random system pods — you MUST verify actual capacity, not assume. Then divide evenly across replicas, not just apply a formula.
>
> Also: resource requests are hard limits for scheduling. If a pod requests 512Mi and node has only 256Mi free, it will NEVER schedule, even if the pod only uses 10Mi at runtime. Requests are for the scheduler, not for actual usage. On the exam, if pods won't schedule, first check if requests are too high via `k describe node`.

## Verify

```bash
./scripts/lab.sh check 23
```

Manual checks:

```bash
# Before the fix: Pending pods with reason "Insufficient memory/cpu"
k get pods -n exercise-23
k describe pod <pod-name> -n exercise-23

# Node capacity
k describe node cka-practice-worker

# After fix — all 3 should be Running on cka-practice-worker
k get pods -n exercise-23 -o wide
```

## Cleanup

```bash
./scripts/lab.sh cleanup 23
```

<details>
<summary>Solution</summary>

```bash
kn exercise-23

# Pods are Pending
k get pods -o wide
k describe pod <pending-pod>
# Events: 0/3 nodes are available: 1 Insufficient cpu, 1 Insufficient memory, ...

# Take web out of the picture, then look at the node
k scale deployment web --replicas=0
k describe node cka-practice-worker
# Allocatable:
#   cpu:     16
#   memory:  30628020Ki
# Allocated resources:
#   cpu      100m
#   memory   50Mi
```

Calculation (numbers from the output above — yours depend on your machine):

```
free CPU     = 16000m − 100m                    = 15900m
free memory  = 30628020Ki / 1024 − 50Mi ≈ 29910Mi − 50Mi = 29860Mi
per replica  = free / 3                         = 5300m CPU, 9953Mi memory
10% buffer   → requests                         = 4770m CPU, 8958Mi memory
```

```bash
k set resources deployment web --requests=cpu=4770m,memory=8958Mi
k scale deployment web --replicas=3

# Verify all 3 pods now Running
k get pods -o wide
```

</details>
