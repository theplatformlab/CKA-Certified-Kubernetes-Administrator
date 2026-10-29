# shellcheck shell=bash
# Exercise 21 — Jobs and CronJobs. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=exercise-21

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  check_eq "Job cleanup-job: completions=3, parallelism=1" \
    "$(jp -n $NS job cleanup-job '{.spec.completions} {.spec.parallelism}')" "3 1"
  check_eq "Job cleanup-job runs busybox:1.37" \
    "$(jp -n $NS job cleanup-job '{.spec.template.spec.containers[0].image}')" "busybox:1.37"
  check_eq "Job cleanup-job completed 3 pods successfully" \
    "$(jp -n $NS job cleanup-job '{.status.succeeded}/{.status.conditions[?(@.type=="Complete")].status}')" "3/True"
  check_contains "Job cleanup-job logged 'Cleanup complete'" \
    "$(kc -n $NS logs job/cleanup-job 2>/dev/null)" "Cleanup complete"

  check_eq "CronJob hourly-backup runs every hour ('0 * * * *')" \
    "$(jp -n $NS cronjob hourly-backup '{.spec.schedule}')" "0 * * * *"
  check_eq "CronJob hourly-backup keeps 3 successful jobs" \
    "$(jp -n $NS cronjob hourly-backup '{.spec.successfulJobsHistoryLimit}')" "3"
  check_eq "CronJob hourly-backup runs busybox:1.37" \
    "$(jp -n $NS cronjob hourly-backup '{.spec.jobTemplate.spec.template.spec.containers[0].image}')" "busybox:1.37"

  check_eq "Job hourly-backup-manual-1 was created from the CronJob" \
    "$(jp -n $NS job hourly-backup-manual-1 '{.metadata.annotations.cronjob\.kubernetes\.io/instantiate}/{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" \
    "manual/CronJob/hourly-backup"
  check_eq "Job hourly-backup-manual-1 completed" \
    "$(jp -n $NS job hourly-backup-manual-1 '{.status.conditions[?(@.type=="Complete")].status}')" "True"
  check_match "Job hourly-backup-manual-1 logged 'Backup at <date>'" \
    "$(kc -n $NS logs job/hourly-backup-manual-1 2>/dev/null)" "Backup at [A-Z][a-z]{2} "
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
