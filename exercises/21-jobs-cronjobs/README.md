# Exercise 21 — Jobs and CronJobs

**Domain:** Workloads & Scheduling (15%)

**Difficulty:** Medium | **Time:** 15 min

---

## Context

Jobs run one or more pods to completion. Unlike Deployments (which keep pods running indefinitely), Jobs don't restart failed pods by default — they just retry. CronJobs schedule Jobs to run on a schedule, like cron in Linux.

On the exam, you'll create both and understand backoff limits, completions, and restart policies. The questions are straightforward: create a job that runs a script to completion, handle failures, maybe schedule it for later.

---

## Tasks

Work in namespace `exercise-21` (`./scripts/lab.sh setup 21` creates it).

1. Create a Job named `cleanup-job` that runs the image `busybox:1.37` with command `echo "Cleanup complete"`. Set it to run 3 times (completions=3) serially (parallelism=1).

2. Verify the Job runs to completion (status should show 3/3). Check the pod logs.

3. Create a CronJob named `hourly-backup` that runs every hour at minute 0 (`0 * * * *`). Use the same busybox image with command `sh -c 'echo "Backup at $(date)"'` (stand-in for a backup script). Let it keep 3 successful job histories (successfulJobsHistoryLimit=3).

4. List CronJobs and check the schedule and the LAST SCHEDULE column.

5. Manually trigger the CronJob once: create a Job named `hourly-backup-manual-1` from it.

6. Verify the manual Job ran and logged `Backup at <date>`.

Validate with `./scripts/lab.sh check 21`.

---

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- **completions=3**: The Job must run 3 times successfully before completion. `completions` is immutable — set it before the Job is created (`k create job ... --dry-run=client -o yaml`, then edit).
- **parallelism=1**: Run one pod at a time, serially.
- **backoffLimit=3**: Retry failed pods up to 3 times, then give up.
- **historyLimit**: Keep this many job history records. Default is 3 for success and 1 for failure.
- For CronJobs, use `spec.schedule` with standard cron syntax (e.g., `0 * * * *` = every hour).
- `kubectl get cronjob` shows when it last ran in the LAST SCHEDULE column (`<none>` until the first run); the next run follows from the schedule.
- To manually trigger a CronJob: `kubectl create job <jobname> --from=cronjob/<cronname>`.

</details>

---

## What tripped me up

I expected completions=3 to mean "run 3 pods in parallel." It doesn't — it means "successfully complete 3 times total." With parallelism=1, those 3 runs are serial. If parallelism=3 and completions=3, all 3 run together.

I also forgot that CronJobs are in the `batch` API group, not `v1`. The YAML syntax is slightly different from Jobs.

When a Job fails, the pod isn't deleted unless the Job's `ttlSecondsAfterFinished` is set. Failed pods stick around for debugging, which is good. But if you're running a test Job, clean it up afterward or you'll have orphan pods.

---

## Verify

```bash
./scripts/lab.sh check 21
```

Manual checks:

```bash
# Check Job completion
k -n exercise-21 get job cleanup-job -o wide
k -n exercise-21 get pod -l job-name=cleanup-job

# Check logs
k -n exercise-21 logs -l job-name=cleanup-job --all-containers=true

# Check CronJob
k -n exercise-21 get cronjob hourly-backup

# Jobs owned by the CronJob (Jobs carry no cronjob label — look at the owner)
k -n exercise-21 get job -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].name

# Check triggered Job
k -n exercise-21 logs job/hourly-backup-manual-1
```

---

## Cleanup

```bash
./scripts/lab.sh cleanup 21
```

Deleting the CronJob also deletes the Jobs it owns, including the manually triggered one.

---

<details>
<summary><b>Solution</b></summary>

**Step 1: Create the Job**

```bash
k create ns exercise-21     # or: ./scripts/lab.sh setup 21

# k create job has no --completions flag (the Job it creates runs once), and
# completions can't be patched afterwards (immutable).
# Generate the YAML, add completions/parallelism, then apply:
k create job cleanup-job -n exercise-21 \
  --image=busybox:1.37 $do \
  -- echo "Cleanup complete" > job.yaml
```

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cleanup-job
  namespace: exercise-21
spec:
  completions: 3
  parallelism: 1
  backoffLimit: 3
  template:
    spec:
      containers:
      - name: cleanup
        image: busybox:1.37
        command: ["echo", "Cleanup complete"]
      restartPolicy: Never
```

**Step 2: Verify Job runs**

```bash
k apply -f job.yaml

k -n exercise-21 get job cleanup-job -w
# Watch until Completions shows 3/3

k -n exercise-21 get pod -l job-name=cleanup-job
# Should show 3 pods

k -n exercise-21 logs -l job-name=cleanup-job
# Logs of all 3 pods (k logs job/cleanup-job shows only one pod)
```

**Step 3: Create CronJob**

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hourly-backup
  namespace: exercise-21
spec:
  schedule: "0 * * * *"  # Every hour at :00
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: busybox:1.37
            command: ["sh", "-c", "echo \"Backup at $(date)\""]  # sh expands $(date)
          restartPolicy: OnFailure
```

```bash
k apply -f cronjob.yaml
```

**Step 4: List CronJobs**

```bash
k -n exercise-21 get cronjob hourly-backup
# NAME            SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# hourly-backup   0 * * * *   <none>     False     0        <none>          20s
```

**Step 5: Manually trigger**

```bash
k -n exercise-21 create job hourly-backup-manual-1 --from=cronjob/hourly-backup
```

**Step 6: Verify manual Job**

```bash
k -n exercise-21 get job hourly-backup-manual-1
k -n exercise-21 logs job/hourly-backup-manual-1
# Backup at Wed Oct 28 21:00:03 UTC 2026
```

</details>

---

## Resources

- [Kubernetes Batch Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Job backoff restart policy](https://kubernetes.io/docs/concepts/workloads/controllers/job/#pod-backoff-failure-policy)
