# Indexed Job with parallelism

**Context:** `kubectl config use-context {{CONTEXT}}`

Create a Job named `frame-render` in namespace `render`:

1. Image `busybox:1.37`, command `sh -c 'echo rendering frame $JOB_COMPLETION_INDEX; sleep 5'`.
2. It must finish after `{{COMPLETIONS}}` successful pods, each with its own completion index (indexed completion mode).
3. At most `{{PARALLELISM}}` pods run at the same time.
4. The Job is marked failed after `{{BACKOFF}}` retries, or when it has been running for more than `{{DEADLINE}}` seconds.
5. Failed pods are not restarted in place (the Job creates new pods instead).

The Job must complete successfully.

## Hints

- `k create job frame-render --image=busybox:1.37 $do -- sh -c '...'` gives the skeleton. `k explain job.spec` lists the other fields.
- The fields are `completions`, `parallelism`, `completionMode`, `backoffLimit` and `activeDeadlineSeconds`. All of them belong in the Job's `spec`, not in the pod template.
- "Not restarted in place" is `restartPolicy: Never` in the pod template.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n render create job frame-render --image=busybox:1.37 $do \
  -- sh -c 'echo rendering frame $JOB_COMPLETION_INDEX; sleep 5' > job.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: frame-render
  namespace: render
spec:
  completions: {{COMPLETIONS}}
  parallelism: {{PARALLELISM}}
  completionMode: Indexed
  backoffLimit: {{BACKOFF}}
  activeDeadlineSeconds: {{DEADLINE}}
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: frame-render
        image: busybox:1.37
        command: ["sh", "-c", "echo rendering frame $JOB_COMPLETION_INDEX; sleep 5"]
```

```bash
k apply -f job.yaml
k -n render get pods -w                          # at most {{PARALLELISM}} running at once
k -n render get job frame-render                 # COMPLETIONS {{COMPLETIONS}}/{{COMPLETIONS}}
k -n render logs -l job-name=frame-render --prefix
```

In `Indexed` mode every pod gets its index (0, 1, 2, ...) in `JOB_COMPLETION_INDEX` and as an annotation, and the Job is done when every index has succeeded once. `activeDeadlineSeconds` beats `backoffLimit`: when the deadline passes, all running pods are stopped and the Job fails with reason `DeadlineExceeded`. Most of a Job's spec is immutable, so if you got a value wrong, delete and recreate the Job.
