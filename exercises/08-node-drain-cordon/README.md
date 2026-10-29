# Exercise 08 — Node Drain and Cordon

> Related: [README — Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25)

Drain a worker node for maintenance, then bring it back. This tests your understanding of pod eviction, DaemonSets, and scheduling.

## Tasks

Work in namespace `exercise-08` (`./scripts/lab.sh setup 08` creates it). Setup also creates the Deployment `drain-test` (3 replicas, `nginx:1.27`, with an `emptyDir` volume) spread across both workers.

The node to maintain is the worker `cka-practice-worker2` (on another practice cluster name: `<cluster>-worker2`).

1. List all nodes and find out which `drain-test` pods run on `cka-practice-worker2`
2. Cordon `cka-practice-worker2` (mark it unschedulable)
3. Verify the node shows `SchedulingDisabled` and that the `drain-test` pods on it are still running (cordon does not evict)
4. Drain `cka-practice-worker2` — handle DaemonSets and the `emptyDir` data
5. Verify that no non-DaemonSet pods are left on the node and `drain-test` is back to 3 ready replicas on the other worker
6. Uncordon the node
7. Scale `drain-test` to 6 replicas and verify new pods get scheduled on `cka-practice-worker2` again

Validate with `./scripts/lab.sh check 08`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

You honestly don't need hints for this one. `k drain --help` tells you everything. The two flags you always need are `--ignore-daemonsets` and `--delete-emptydir-data`.

</details>

## What tripped me up

> I ran `k drain worker-1` without `--ignore-daemonsets` and it failed immediately. The error message is long and mentions DaemonSet-managed pods, but I didn't read it carefully — I just thought drain was broken. Always use `--ignore-daemonsets --delete-emptydir-data`. Every time. No exceptions.
>
> Subtle one: `k cordon` marks the node unschedulable but does NOT evict existing pods. I cordoned a node thinking it would move pods off it, then spent 5 minutes wondering why pods were still there. Cordon = "don't schedule new pods here." Drain = "evict everything and cordon."

## Verify

```bash
./scripts/lab.sh check 08
```

Manual checks:

```bash
# After cordon: the worker shows SchedulingDisabled
k get nodes

# After drain: only DaemonSet pods (kindnet, kube-proxy) left on the node
k get pods -A -o wide --field-selector spec.nodeName=cka-practice-worker2

# After uncordon + scale: pods spread across both workers again
k -n exercise-08 get pods -o wide
```

## Cleanup

```bash
./scripts/lab.sh cleanup 08     # also uncordons cka-practice-worker2
```

<details>
<summary>Solution</summary>

```bash
# List nodes and current pod placement
k get nodes
k -n exercise-08 get pods -o wide

# Cordon
k cordon cka-practice-worker2
k get nodes
# cka-practice-worker2 should show Ready,SchedulingDisabled
k -n exercise-08 get pods -o wide
# The drain-test pods on cka-practice-worker2 are still Running

# Drain (fails without both flags: DaemonSet pods and emptyDir data)
k drain cka-practice-worker2 --ignore-daemonsets --delete-emptydir-data

# Verify eviction
k -n exercise-08 get pods -o wide
# All 3 drain-test pods now run on cka-practice-worker
k get pods -A --field-selector spec.nodeName=cka-practice-worker2
# Only DaemonSet pods should remain

# Uncordon
k uncordon cka-practice-worker2
k get nodes
# cka-practice-worker2 should be Ready (no SchedulingDisabled)

# Scale up — new pods should land on cka-practice-worker2 too
k -n exercise-08 scale deployment drain-test --replicas=6
k -n exercise-08 get pods -o wide
```

Note: uncordoning does not move the existing pods back. Only new pods (here from the scale-up) use the node again.

</details>
