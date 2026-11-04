# CronJob

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `backup`:

1. Create a CronJob named `db-backup`:
   - runs every day at {{HOUR}}:00
   - image `busybox:1.37`, command `sh -c 'echo backup done'`
   - keeps the last `{{KEEP}}` successful and the last `1` failed Jobs
   - concurrency policy `Forbid`
   - suspended
2. Test it once right now: create a Job named `db-backup-manual` from the CronJob. The Job must complete successfully.

## Hints

- `kubectl create cronjob ... --schedule=... -- <command>`, then add the remaining fields in the YAML.
- `suspend`, `concurrencyPolicy`, `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` sit directly under `spec`.
- `kubectl create job <name> --from=cronjob/<cronjob>` works even while the CronJob is suspended.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n backup create cronjob db-backup --image=busybox:1.37 --schedule="0 {{HOUR_NUM}} * * *" $do \
  -- sh -c 'echo backup done' > cj.yaml
```

```yaml
spec:
  schedule: "0 {{HOUR_NUM}} * * *"
  suspend: true
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: {{KEEP}}
  failedJobsHistoryLimit: 1
  jobTemplate:
    # ... unchanged ...
```

```bash
k apply -f cj.yaml
k -n backup create job db-backup-manual --from=cronjob/db-backup
k -n backup wait --for=condition=Complete job/db-backup-manual
k -n backup logs job/db-backup-manual
```

`--from=cronjob/...` works even while the CronJob is suspended. `suspend` only stops the scheduler from creating Jobs.
