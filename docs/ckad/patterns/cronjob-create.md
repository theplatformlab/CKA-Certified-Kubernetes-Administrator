# CronJob Creation Pattern

**Curriculum domain:** Application Design and Build (20%, choosing the right workload resource)

---

## Problem Scenario

> Create a CronJob named 'backup-runner' that runs at 2:30 AM every day, executes `backup.sh`, and keeps only the last 3 job runs in history.

---

## Quick Command (Fastest Method)

```bash
kubectl create cronjob backup-runner \
  --image=busybox \
  --schedule="30 2 * * *" \
  -- /bin/sh -c "echo 'Running backup'; backup.sh"
```

---

## Full YAML (When Command Doesn't Work)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-runner
spec:
  # Cron format: minute hour day-of-month month day-of-week
  # "30 2 * * *" = 2:30 AM every day
  schedule: "30 2 * * *"
  
  # Keep only 3 successful runs in history
  successfulJobsHistoryLimit: 3
  
  # Keep only 1 failed run in history
  failedJobsHistoryLimit: 1
  
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: ubuntu:22.04
            command:
              - /bin/bash
              - -c
              - |
                echo "Backup started at $(date)"
                /path/to/backup.sh
                echo "Backup completed"
          restartPolicy: OnFailure
```

---

## Cron Schedule Format

```
┌──────── minute (0-59)
│ ┌────── hour (0-23)
│ │ ┌──── day of month (1-31)
│ │ │ ┌── month (1-12)
│ │ │ │ ┌ day of week (0-6, 0=Sunday)
│ │ │ │ │
* * * * *
```

### Common Schedules

| Schedule | Meaning |
|----------|---------|
| `0 2 * * *` | 2:00 AM every day |
| `30 */4 * * *` | 12:30, 4:30, 8:30 AM/PM (every 4 hours at :30) |
| `0 0 1 * *` | 12:00 AM on 1st of each month |
| `0 0 * * 0` | 12:00 AM every Sunday |
| `*/5 * * * *` | Every 5 minutes |
| `0 9-17 * * 1-5` | 9 AM - 5 PM Mon-Fri |

---

## Verification

```bash
# View CronJob
kubectl get cronjob backup-runner
# NAME            SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
# backup-runner   30 2 * * *    False     0        N/A             5s

# View running jobs
kubectl get job -l cronjob=backup-runner

# View job history
kubectl get job -l cronjob=backup-runner --sort-by='.metadata.creationTimestamp'

# Check job logs (if already run)
kubectl logs job/<job-name>

# Manually trigger (test before schedule time)
kubectl create job backup-runner-manual-test --from=cronjob/backup-runner

# View CronJob details
kubectl describe cronjob backup-runner
```

---

## Common Exam Mistakes

| Mistake | Fix |
|---------|-----|
| Schedule wrong timezone | Use UTC always; exam cluster is UTC |
| Command not executing | Use `-- /bin/sh -c "command here"` properly |
| Job never completes | Add `restartPolicy: OnFailure` |
| Too many old jobs piling up | Set `successfulJobsHistoryLimit` and `failedJobsHistoryLimit` |
| Image wrong | Specify image that has your script; use Ubuntu/Alpine if custom image not provided |
| Script location wrong | Script must exist in image or download it first |

---

## Real Exam Variations

### Variation 1: Run Every 30 Minutes
```bash
kubectl create cronjob mybackup \
  --image=ubuntu \
  --schedule="*/30 * * * *" \
  -- backup.sh
```

### Variation 2: Run with Custom Command
```yaml
jobTemplate:
  spec:
    template:
      spec:
        containers:
        - name: worker
          image: python:3.9
          command: ["python", "-c", "import time; print('task'); time.sleep(10)"]
```

### Variation 3: Run Once a Week
```bash
--schedule="0 3 * * 1"  # Monday 3 AM
```

### Variation 4: Suspend CronJob (Don't Run)
```bash
kubectl patch cronjob backup-runner -p '{"spec":{"suspend":true}}'
# Resume:
kubectl patch cronjob backup-runner -p '{"spec":{"suspend":false}}'
```

---

## Speed Tip

Memorize most common schedules:
- Daily: `0 2 * * *`
- Hourly: `0 * * * *`
- Every 30 min: `*/30 * * * *`
- Weekly (Monday 3AM): `0 3 * * 1`

If exam asks for custom schedule—copy template, replace schedule field only.

---

## Testing the Schedule Before Exam Day

```bash
# Test if schedule is valid
kubectl create cronjob test-cron --image=busybox --schedule="0 2 * * *" --dry-run=client -o yaml

# Run job immediately without waiting for cron
kubectl create job test-manual --from=cronjob/backup-runner
```
