# Roll back a broken rollout

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `payment-service` in namespace `payments` was updated several times. The latest update broke it.

1. Find the revision that introduced the broken version. Write its revision number into `{{WORKDIR}}/broken-revision.txt`.
2. Roll the Deployment back to the revision right before the broken one.
3. Future rollouts of `payment-service` must never drop below 3 available pods and add at most one extra pod at a time: set the rolling update strategy to `maxSurge: 1` and `maxUnavailable: 0`.
4. All 3 replicas must be Ready.

## Hints

- `kubectl rollout history deploy/<name>` lists revisions with their change-cause.
- `kubectl rollout history ... --revision=<n>` shows the pod template (image) of one revision.
- `kubectl rollout undo ... --to-revision=<n>`
- The strategy lives in `spec.strategy.rollingUpdate` of the Deployment, not in the pod template (`kubectl explain deploy.spec.strategy`).

## Solution

```bash
k config use-context {{CONTEXT}}
k -n payments rollout history deploy payment-service
# REVISION  CHANGE-CAUSE
# 1         initial release nginx:1.27
# 2         upgrade to nginx:1.28
# 3         upgrade to nginx:1.28.99      <- ImagePullBackOff
k -n payments rollout history deploy payment-service --revision=3   # confirm the image
echo 3 > {{WORKDIR}}/broken-revision.txt

k -n payments rollout undo deploy payment-service --to-revision=2
k -n payments rollout status deploy payment-service

k -n payments patch deploy payment-service \
  -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
```

`rollout undo` without `--to-revision` also goes back exactly one revision. Spelling out the target is safer when you are under pressure. After the undo, revision 2 is renumbered to 4: the history only ever moves forward. Changing the strategy creates no new revision: it is not part of the pod template.
