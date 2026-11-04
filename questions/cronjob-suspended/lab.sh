# shellcheck shell=bash
# CronJob. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=backup

lab_params() {
  local hour; hour="$(rand_int 0 6)"
  echo "HOUR_NUM=$hour"
  echo "HOUR=$(printf %02d "$hour")"
  echo "KEEP=$(pick 2 3 5)"
}

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  check_gate "CronJob db-backup exists" exists -n $NS cronjob db-backup
  check_match "Schedule is daily at $HOUR:00" "$(jp -n $NS cronjob db-backup '{.spec.schedule}')" "^0 0?$HOUR_NUM \\* \\* \\*\$"
  check_eq "Image busybox:1.37" \
    "$(jp -n $NS cronjob db-backup '{.spec.jobTemplate.spec.template.spec.containers[0].image}')" "busybox:1.37"
  check_eq "History limits $KEEP successful / 1 failed" \
    "$(jp -n $NS cronjob db-backup '{.spec.successfulJobsHistoryLimit}/{.spec.failedJobsHistoryLimit}')" "$KEEP/1"
  check_eq "concurrencyPolicy Forbid" "$(jp -n $NS cronjob db-backup '{.spec.concurrencyPolicy}')" "Forbid"
  check_eq "CronJob is suspended" "$(jp -n $NS cronjob db-backup '{.spec.suspend}')" "true"
  check_eq "Job db-backup-manual was created from the CronJob" \
    "$(jp -n $NS job db-backup-manual '{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" "CronJob/db-backup"
  check_eq "Job db-backup-manual completed successfully" "$(jp -n $NS job db-backup-manual '{.status.succeeded}')" "1"
  check_contains "Job output is 'backup done'" "$(kc -n $NS logs job/db-backup-manual 2>/dev/null)" "backup done"
}
