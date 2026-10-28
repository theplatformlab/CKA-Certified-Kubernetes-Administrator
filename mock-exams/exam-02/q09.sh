# shellcheck shell=bash
# Q9 — CronJob
Q_CLUSTER=practice
NS=backup

q_setup() { ensure_ns "$NS"; }

q_check() {
  check_gate "CronJob db-backup exists" exists -n $NS cronjob db-backup
  check_match "Schedule is daily at 02:00" "$(jp -n $NS cronjob db-backup '{.spec.schedule}')" '^0 2 \* \* \*$'
  check_eq "Image busybox:1.37" \
    "$(jp -n $NS cronjob db-backup '{.spec.jobTemplate.spec.template.spec.containers[0].image}')" "busybox:1.37"
  check_eq "History limits 3 successful / 1 failed" \
    "$(jp -n $NS cronjob db-backup '{.spec.successfulJobsHistoryLimit}/{.spec.failedJobsHistoryLimit}')" "3/1"
  check_eq "concurrencyPolicy Forbid" "$(jp -n $NS cronjob db-backup '{.spec.concurrencyPolicy}')" "Forbid"
  check_eq "CronJob is suspended" "$(jp -n $NS cronjob db-backup '{.spec.suspend}')" "true"
  check_eq "Job db-backup-manual was created from the CronJob" \
    "$(jp -n $NS job db-backup-manual '{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" "CronJob/db-backup"
  check_eq "Job db-backup-manual completed successfully" "$(jp -n $NS job db-backup-manual '{.status.succeeded}')" "1"
  check_contains "Job output is 'backup done'" "$(kc -n $NS logs job/db-backup-manual 2>/dev/null)" "backup done"
}
