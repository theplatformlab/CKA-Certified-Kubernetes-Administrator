# Rollout stuck in a namespace with a quota

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `invoice-api` in namespace `billing` should run {{REPLICAS}} replicas, but its rollout never finishes and fewer pods exist.

Find out why, then fix it:

1. The team decided to set the CPU request of container `api` to `{{CPU_REQ}}`. Keep the image, the memory request and limit, and `{{REPLICAS}}` replicas.
2. Do not modify the ResourceQuota of the namespace.
3. When you are done, all `{{REPLICAS}}` pods must be running and ready.

## Hints

- `k -n billing rollout status deploy invoice-api` hangs. Pods are created by the ReplicaSet, so look at its events: `k -n billing describe rs`.
- `k -n billing describe resourcequota`: how much CPU is requested already, and what is the limit?
- Every pod's CPU request counts against `requests.cpu` of the quota. Lower the request with `k set resources`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n billing get deploy,rs,pods                        # one pod short of {{REPLICAS}}
k -n billing describe rs | grep -A2 Warning
# FailedCreate ... exceeded quota: billing-quota, requested: requests.cpu=300m, used: ..., limited: ...
k -n billing describe resourcequota billing-quota

k -n billing set resources deploy invoice-api -c api --requests=cpu={{CPU_REQ}}
k -n billing rollout status deploy invoice-api
k -n billing get pods -o custom-columns=NAME:.metadata.name,CPU:.spec.containers[0].resources.requests.cpu
```

The ResourceQuota is checked by an admission plugin when a pod is created, so the error shows up as a `FailedCreate` event on the ReplicaSet, not on the Deployment or a pod. At `300m` the quota has room for one pod less than needed. `set resources` with only `--requests=cpu=...` keeps the memory request and limit as they are. The Deployment uses the `Recreate` strategy, so the old pods are removed first and the new ones fit. With a rolling update, old and new pods would count against the quota at the same time (terminating pods too, until their grace period ends), and the ReplicaSet retries failed creations with growing back-off.
