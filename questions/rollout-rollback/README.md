# Roll back a broken rollout

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `payment-service` in namespace `payments` was updated several times. The latest update broke it.

1. Find the revision that introduced the broken version. Write its revision number into `{{WORKDIR}}/broken-revision.txt`.
2. Roll the Deployment back to the revision right before the broken one.
3. All 3 replicas must be Ready.

## Hints

- `kubectl rollout history deploy/<name>` lists revisions with their change-cause.
- `kubectl rollout history ... --revision=<n>` shows the pod template (image) of one revision.
- `kubectl rollout undo ... --to-revision=<n>`

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
```

`rollout undo` without `--to-revision` also goes back exactly one revision. Spelling out the target is safer when you are under pressure. After the undo, revision 2 is renumbered to 4: the history only ever moves forward.
