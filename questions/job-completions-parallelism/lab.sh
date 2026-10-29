# shellcheck shell=bash
# Indexed Job with completions/parallelism/backoffLimit/activeDeadlineSeconds. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=render

lab_params() {
  echo "COMPLETIONS=$(rand_int 5 8)"
  echo "PARALLELISM=$(pick 2 3)"
  echo "BACKOFF=$(pick 2 3 4)"
  echo "DEADLINE=$(pick 120 180 240)"
}

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  local j='{.spec' t='{.spec.template.spec'
  check_gate "Job frame-render exists" exists -n $NS job frame-render
  check_eq "Image busybox:1.37, restartPolicy Never" \
    "$(jp -n $NS job frame-render "$t.containers[0].image} $t.restartPolicy}")" "busybox:1.37 Never"
  check_eq "completions $COMPLETIONS, parallelism $PARALLELISM" \
    "$(jp -n $NS job frame-render "$j.completions} $j.parallelism}")" "$COMPLETIONS $PARALLELISM"
  check_eq "backoffLimit $BACKOFF, activeDeadlineSeconds $DEADLINE" \
    "$(jp -n $NS job frame-render "$j.backoffLimit} $j.activeDeadlineSeconds}")" "$BACKOFF $DEADLINE"
  check_eq "completionMode Indexed" "$(jp -n $NS job frame-render "$j.completionMode}")" "Indexed"
  check_eq "Job completed: $COMPLETIONS succeeded, indexes 0-$((COMPLETIONS - 1))" \
    "$(jp -n $NS job frame-render '{.status.succeeded} {.status.completedIndexes} {.status.conditions[?(@.type=="Complete")].status}')" \
    "$COMPLETIONS 0-$((COMPLETIONS - 1)) True"
  check_contains "The pod with index 0 logged 'rendering frame 0'" \
    "$(kc -n $NS logs -l job-name=frame-render,batch.kubernetes.io/job-completion-index=0 --tail=-1 2>/dev/null)" "rendering frame 0"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
