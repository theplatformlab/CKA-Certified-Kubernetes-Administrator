# Which pods are evicted first

**Context:** `kubectl config use-context {{CONTEXT}}`

The nodes of the cluster are running low on memory. Namespace `telemetry` runs several Deployments, and the team wants to know which of its pods the kubelet would evict **first** under node pressure, based on their Quality of Service class.

Write the names of all those pods in namespace `telemetry`, one per line, into `{{WORKDIR}}/evict-first.txt`. Do not change the workloads.

## Hints

- The kubelet evicts pods of QoS class `BestEffort` first, then `Burstable` pods that use more than they requested, `Guaranteed` pods last.
- Kubernetes writes the class into every pod: `.status.qosClass`.
- `k -n telemetry get pod -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass` lists it for all pods at once.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n telemetry get pod -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
k -n telemetry get pod -o jsonpath='{range .items[?(@.status.qosClass=="BestEffort")]}{.metadata.name}{"\n"}{end}' \
  > {{WORKDIR}}/evict-first.txt
cat {{WORKDIR}}/evict-first.txt      # the pods of {{BE_ONE}} and {{BE_TWO}}
```

A pod is `BestEffort` only when none of its containers has any CPU or memory request or limit; these are the pods of `{{BE_ONE}}` and `{{BE_TWO}}`. Reading the Deployments can mislead: a container with limits but no requests is `Guaranteed` (requests default to the limits), and one container without resources next to a fully specified one makes the pod `Burstable`, not `BestEffort`. `.status.qosClass` settles it. Pod names have a random suffix, so copy them from the live pods.
