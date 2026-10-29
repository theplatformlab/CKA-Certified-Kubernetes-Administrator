# Exercise 01 — Pod Basics

> Related: [Pod skeleton](../../skeletons/pod.yaml) | [README — Workloads & Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Create a pod with specific resource requests, labels, and verify it's running.

## Tasks

Work in namespace `exercise-01` (`./scripts/lab.sh setup 01` creates it).

1. Create a pod named `web` in namespace `exercise-01` with these specs:
   - Image: `nginx:1.27`
   - Labels: `app=web`, `tier=frontend`
   - Resource requests: `64Mi` memory, `100m` CPU
   - Resource limits: `128Mi` memory, `250m` CPU
2. Verify the pod is running and has the correct labels
3. Get the pod's IP address using `-o wide`
4. Add a new label `version=v1` to the running pod
5. Remove the `tier` label from the pod

Validate with `./scripts/lab.sh check 01`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Use `k run` to generate the YAML, then edit it to add resources
- `k label pod` to add labels, `k label pod <name> <label>-` to remove them
- Resource fields go under `spec.containers[].resources`

</details>

## What tripped me up

> I created the pod in `default` the first time because I forgot `-n exercise-01` on the `k apply`. Zero points — the grader checks the exact namespace. Now I always run `kn <namespace>` before touching anything. Cost me 4 minutes the first time.
>
> Also: I kept trying to add resources directly in `k run`. You can't. You have to generate the YAML with `$do`, edit it, then apply. Don't fight the CLI — just redirect to a file.

## Verify

```bash
./scripts/lab.sh check 01
```

Manual checks:

```bash
# Pod should be Running
k get pod web -n exercise-01

# Should show app=web,version=v1
k get pod web -n exercise-01 --show-labels

# Should show IP
k get pod web -n exercise-01 -o wide
```

## Cleanup

```bash
./scripts/lab.sh cleanup 01
```

<details>
<summary>Solution</summary>

```bash
# Namespace (or: ./scripts/lab.sh setup 01)
k create ns exercise-01

# Generate pod YAML
k run web -n exercise-01 --image=nginx:1.27 --labels=app=web,tier=frontend $do > pod.yaml
```

Edit `pod.yaml` to add resources:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: exercise-01
  labels:
    app: web
    tier: frontend
spec:
  containers:
  - name: web
    image: nginx:1.27
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "250m"
```

```bash
k apply -f pod.yaml

# Verify
k get pod web -n exercise-01 --show-labels
k get pod web -n exercise-01 -o wide

# Add label
k label pod web -n exercise-01 version=v1

# Remove label
k label pod web -n exercise-01 tier-
```

</details>
