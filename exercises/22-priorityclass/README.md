# Exercise 22 — PriorityClass

**Domain:** Workloads & Scheduling (15%)

**Difficulty:** Medium | **Time:** 15 min

---

## Context

PriorityClass defines the relative importance of pods. When nodes have limited resources, the scheduler prioritizes high-priority pods first. If a high-priority pod can't fit on any node, the scheduler can evict lower-priority pods to make room (preemption).

On the exam, you'll create PriorityClasses and assign them to pods. You need to know the difference between priority values, how preemption works, and how to debug which pods get scheduled when resources are tight.

---

## Tasks

Work in namespace `exercise-22` (`./scripts/lab.sh setup 22` creates it). PriorityClasses themselves are cluster-scoped.

1. Create a PriorityClass named `high-priority` with value 1000 and preemptionPolicy set to `PreemptLowerPriority` (not the global default).

2. Create a PriorityClass named `low-priority` with value 10 and preemptionPolicy set to `Never` (not the global default).

3. Create a Pod named `critical-app` in `exercise-22` using `nginx:1.28` and assign it to the `high-priority` class.

4. Create a Pod named `background-job` in `exercise-22` using `busybox:1.37` to run `sleep 3600` and assign it to the `low-priority` class.

5. Verify both pods are running. Check their priority values with `kubectl get pod -o json` and filter for `priority` and `priorityClassName`.

6. Optional: drain a node to trigger preemption and observe which pod gets evicted (uncordon it afterwards; not validated).

Validate with `./scripts/lab.sh check 22`.

---

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- **Priority values**: Higher number = higher priority. System pods use 2000000000 (reserved by Kubernetes). Use 1-1000 for application priorities to stay safe.
- **preemptionPolicy: PreemptLowerPriority**: Allow this priority class to evict lower-priority pods if resources are scarce.
- **preemptionPolicy: Never**: Pods of this class never evict other pods; if they can't fit, they just wait (ahead of lower-priority pods in the queue). They can still be preempted by higher-priority pods.
- Default priority is 0. Pods without an explicit PriorityClass use priority 0.
- You must create a PriorityClass with `kind: PriorityClass` (not a built-in). PriorityClasses are cluster-wide, not namespaced.
- Preemption only happens when the scheduler can't fit a pod and has eviction candidates. It's not automatic.

</details>

---

## What tripped me up

I thought higher priority pods always run first. They do — but only when the scheduler evaluates new pods. If low-priority pods are already running and using resources, the high-priority pod still has to wait unless preemption kicks in.

I also confused priority (user-defined) with QoS (Quality of Service: Guaranteed, Burstable, BestEffort), which is automatic based on resource limits. They're different and work together.

Typo in `priorityClassName`? I expected the pod to sit in Pending, but the Priority admission plugin rejects it right away: `no PriorityClass with name ... was found`. Read the error — and remember to create the PriorityClass before the Pod.

---

## Verify

```bash
./scripts/lab.sh check 22
```

Manual checks:

```bash
# Check PriorityClasses exist
k get priorityclass -o wide

# Check pod priority
k -n exercise-22 get pod -o wide

# Fast priority check (all pods in one table)
k -n exercise-22 get pod -o custom-columns=NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIORITY:.spec.priority

# Single pod checks (exam-safe, no jq needed)
k -n exercise-22 get pod critical-app -o jsonpath='{.spec.priorityClassName}{" "}{.spec.priority}{"\n"}'
k -n exercise-22 get pod background-job -o jsonpath='{.spec.priorityClassName}{" "}{.spec.priority}{"\n"}'

# Check pod scheduling
k -n exercise-22 describe pod critical-app
k -n exercise-22 describe pod background-job

# Monitor preemption (if draining a node)
k get events --sort-by='.lastTimestamp'
```

---

## Cleanup

```bash
./scripts/lab.sh cleanup 22    # namespace, both PriorityClasses, uncordons all nodes
```

---

<details>
<summary><b>Solution</b></summary>

**Step 1: Create PriorityClasses**

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "High priority for critical applications"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 10
preemptionPolicy: Never
globalDefault: false
description: "Low priority for background jobs"
```

```bash
k apply -f priorityclasses.yaml
k create ns exercise-22     # or: ./scripts/lab.sh setup 22
```

Verify:
```bash
k get priorityclass
# NAME              VALUE        GLOBAL-DEFAULT   AGE
# high-priority     1000         false            5s
# low-priority      10           false            5s
```

**Step 2: Create Pods with PriorityClasses**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-app
  namespace: exercise-22
spec:
  priorityClassName: high-priority
  containers:
  - name: app
    image: nginx:1.28
---
apiVersion: v1
kind: Pod
metadata:
  name: background-job
  namespace: exercise-22
spec:
  priorityClassName: low-priority
  containers:
  - name: worker
    image: busybox:1.37
    command: ["sleep", "3600"]
```

```bash
k apply -f pods.yaml
```

**Step 3: Verify Priority**

```bash
k -n exercise-22 get pod -o wide
k -n exercise-22 get pod critical-app -o json | jq '.spec.priorityClassName'
# "high-priority"

k -n exercise-22 get pod critical-app -o json | jq '.spec.priority'
# 1000

k -n exercise-22 get pod background-job -o json | jq '.spec.priority'
# 10
```

**Step 4: Trigger Preemption (optional)**

If you have a multi-node cluster, drain a node:

```bash
k drain <node> --ignore-daemonsets --delete-emptydir-data --force   # --force: the pods are unmanaged
# afterwards
k uncordon <node>
```

Monitor with:
```bash
k get events --sort-by='.lastTimestamp'
```

Careful: drain itself ignores priority — it evicts every pod on the node, and bare pods like these are gone for good (no controller recreates them, so re-apply `pods.yaml` before running the check). Preemption is done by the scheduler: it happens when a pending higher-priority pod can't fit anywhere, and then the lowest-priority pods (`background-job`) are evicted first.

**Step 5: Cleanup**

```bash
./scripts/lab.sh cleanup 22
```

</details>

---

## Resources

- [Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
- [PriorityClass API](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/priority-class-v1/)
- [Preemption and Priority](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/#preemption)
