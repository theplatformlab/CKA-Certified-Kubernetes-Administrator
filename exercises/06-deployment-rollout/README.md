# Exercise 06 — Deployment Rolling Update and Rollback

> Related: [Deployment skeleton](../../skeletons/deployment.yaml) | [README — Workloads & Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Create a Deployment, perform a rolling update, check rollout history, and rollback.

## Tasks

Work in namespace `exercise-06` (`./scripts/lab.sh setup 06` creates it).

1. Create a Deployment named `webapp` in `exercise-06` with:
   - 3 replicas, pod label `app=webapp`
   - One container named `nginx`, image `nginx:1.28`
   - Strategy: RollingUpdate with maxSurge=1, maxUnavailable=0
   - Record the change cause (`kubernetes.io/change-cause` annotation)
2. Verify all 3 replicas are running
3. Update the image of container `nginx` to `nginx:1.29` and record the change
4. Watch the rollout status
5. Check rollout history — you should see 2 revisions, each with a CHANGE-CAUSE
6. Rollback to the previous version (nginx:1.28)
7. Verify the rollback worked by checking the image

Validate with `./scripts/lab.sh check 06`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k create deployment webapp --image=nginx:1.28 --replicas=3`
- `k set image deployment/webapp` to update
- `k rollout status`, `k rollout history`, `k rollout undo`
- Annotate with `kubernetes.io/change-cause` to track changes in rollout history

</details>

## What tripped me up

> I used `--record` on every deployment command because that's what older guides taught. It's deprecated and removed in v1.35 — the CHANGE-CAUSE column shows `<none>`. The correct way: annotate the deployment with `kubernetes.io/change-cause` after each change. It's one extra command but it actually works.
>
> Also: I forgot that `k rollout undo` creates a NEW revision, not a revert. After undo, I had revisions 2, 3 (revision 1 was gone — it became revision 3). My history looked weird and I thought something broke. That's just how it works — undo creates revision N+1 with the old spec.
>
> **Why `--overwrite` on the second annotation?** The `kubernetes.io/change-cause` annotation lives on the Deployment object itself, not on individual revisions. When you update the image, the Deployment object remains the same. The old annotation persists, so you need `--overwrite` to change its value. First annotation (initial deploy) doesn't need it because the key doesn't exist yet. Second annotation (after update) needs it because the key already exists. Without `--overwrite`, the command would error with "annotation already exists".

## Verify

```bash
./scripts/lab.sh check 06
```

Manual checks:

```bash
# After initial deploy
k get deploy webapp -n exercise-06
k get rs -n exercise-06

# After rollback — image should be nginx:1.28
k get deploy webapp -n exercise-06 -o jsonpath='{.spec.template.spec.containers[0].image}'

# History: revision 2 (nginx:1.29) and revision 3 (the rollback), both with a CHANGE-CAUSE
k rollout history deployment/webapp -n exercise-06
```

## Cleanup

```bash
./scripts/lab.sh cleanup 06
```

<details>
<summary>Solution</summary>

```bash
k create ns exercise-06     # or: ./scripts/lab.sh setup 06

# Create deployment
k create deployment webapp -n exercise-06 --image=nginx:1.28 --replicas=3 $do > deploy.yaml
```

Edit `deploy.yaml` to add rolling update strategy, then apply:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: exercise-06
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webapp
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
```

```bash
k apply -f deploy.yaml
# First annotation — no --overwrite needed because the key doesn't exist yet
k annotate deployment webapp -n exercise-06 kubernetes.io/change-cause="initial deploy nginx:1.28"

# Verify
k get deploy webapp -n exercise-06
k get pods -n exercise-06

# Update image
k set image deployment/webapp nginx=nginx:1.29 -n exercise-06
# Second annotation — MUST use --overwrite because kubernetes.io/change-cause already exists on the Deployment object
# The annotation key lives on the Deployment, not on individual revisions, so it persists across updates
k annotate deployment webapp -n exercise-06 kubernetes.io/change-cause="update to nginx:1.29" --overwrite

# Watch rollout
k rollout status deployment/webapp -n exercise-06

# Check history
k rollout history deployment/webapp -n exercise-06

# Rollback
k rollout undo deployment/webapp -n exercise-06

# Verify rollback
k get deploy webapp -n exercise-06 -o jsonpath='{.spec.template.spec.containers[0].image}'
# Should output: nginx:1.28
```

</details>
