# PriorityClasses

**Context:** `kubectl config use-context {{CONTEXT}}`

1. Create a PriorityClass named `critical-workload` with value `1000000` and description `critical`.
2. Create a PriorityClass named `standard-workload` with value `1000` and `preemptionPolicy: Never`.
   Neither PriorityClass may be the global default.
3. In namespace `priority`, create a Deployment `critical-app` with 2 replicas, image `busybox:1.37` and command `sleep 3600`, using PriorityClass `critical-workload`.
4. In namespace `priority`, create a pod `batch-job` with image `busybox:1.37` and command `sleep 3600`, using PriorityClass `standard-workload`.

## Hints

- `kubectl create priorityclass <name> --value=... --description=... --preemption-policy=...`
- Pods reference the class with `spec.priorityClassName`; for a Deployment it goes into the pod template.
- Check the result with `kubectl get pods -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority`.

## Solution

```bash
k config use-context {{CONTEXT}}
k create priorityclass critical-workload --value=1000000 --description=critical
k create priorityclass standard-workload --value=1000 --preemption-policy=Never

k -n priority create deployment critical-app --image=busybox:1.37 --replicas=2 $do -- sleep 3600 > critical.yaml
# add  spec.template.spec.priorityClassName: critical-workload
k apply -f critical.yaml

k -n priority run batch-job --image=busybox:1.37 $do --command -- sleep 3600 > batch.yaml
# add  spec.priorityClassName: standard-workload
k apply -f batch.yaml
k -n priority get pods -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority
```

The admission controller turns `priorityClassName` into the numeric `spec.priority` at creation. `preemptionPolicy: Never` means pods of that class never evict others to get scheduled, but they can still be preempted themselves.
