# Pods Pending on a tainted node

**Context:** `kubectl config use-context {{CONTEXT}}`

The 3 pods of Deployment `etl-worker` in namespace `analytics` stay `Pending`. They have to run on node `{{NODE_W2}}`, the only node with fast local disks.

Fix it so that all 3 replicas run on `{{NODE_W2}}`:

1. Do not modify the Deployment (no tolerations, no changed nodeSelector).
2. Fix the node instead, but change only what blocks the pods. Every other label and taint of `{{NODE_W2}}` must stay.

## Hints

- `k -n analytics describe pod -l app=etl-worker`: the `FailedScheduling` event says why each node was rejected.
- `k describe node {{NODE_W2}} | grep -A3 Taints`. Which taint has an effect that blocks scheduling?
- `PreferNoSchedule` only makes the scheduler avoid a node, it doesn't block pods. Remove the `NoSchedule` taint with `k taint node ... <key>:NoSchedule-`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n analytics describe pod -l app=etl-worker | grep -A3 FailedScheduling
# 0/3 nodes are available: 1 node(s) didn't match Pod's node affinity/selector,
# 2 node(s) had untolerated taint(s) ...        (the control plane and {{NODE_W2}})
k get node {{NODE_W2}} -o jsonpath='{.spec.taints}'
# maintenance.example.com/window=planned:NoSchedule, team.example.com/analytics=true:PreferNoSchedule

k taint node {{NODE_W2}} maintenance.example.com/window:NoSchedule-
k -n analytics get pods -o wide              # 3x Running on {{NODE_W2}}
```

The nodeSelector `disktype=nvme` leaves only `{{NODE_W2}}`, and its `NoSchedule` taint rejects every pod without a matching toleration. `PreferNoSchedule` is only a soft preference: when no other node fits, the scheduler still uses the node, so that taint can stay. A trailing `-` removes a taint. With `key:Effect-` only that effect is removed; `key-` removes the key with all effects.
