# shellcheck shell=bash
# Memory-backed emptyDir shared by two containers plus a generic ephemeral volume. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=scratch-space
P=etl-worker

lab_params() {
  echo "CACHE_SIZE=$(pick 32Mi 64Mi 128Mi)"
  echo "SCRATCH_SIZE=$(pick 1Gi 2Gi 3Gi)"
}

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  local v='{.spec.volumes[?(@.name=="cache")]' s='{.spec.volumes[?(@.name=="scratch")].ephemeral.volumeClaimTemplate.spec'
  check_gate "Pod $P exists" exists -n $NS pod $P
  check_eq "Volume cache is an emptyDir with medium Memory and sizeLimit $CACHE_SIZE" \
    "$(jp -n $NS pod $P "$v.emptyDir.medium} $v.emptyDir.sizeLimit}")" "Memory $CACHE_SIZE"
  check_eq "Volume scratch is a generic ephemeral volume: StorageClass standard, ReadWriteOnce, $SCRATCH_SIZE" \
    "$(jp -n $NS pod $P "$s.storageClassName} $s.accessModes[*]} $s.resources.requests.storage}")" "standard ReadWriteOnce $SCRATCH_SIZE"
  check_eq "producer (busybox:1.37) mounts cache at /cache and scratch at /scratch" \
    "$(jp -n $NS pod $P '{.spec.containers[?(@.name=="producer")].image} {.spec.containers[?(@.name=="producer")].volumeMounts[?(@.name=="cache")].mountPath} {.spec.containers[?(@.name=="producer")].volumeMounts[?(@.name=="scratch")].mountPath}')" \
    "busybox:1.37 /cache /scratch"
  check_eq "consumer (busybox:1.37) mounts cache at /input" \
    "$(jp -n $NS pod $P '{.spec.containers[?(@.name=="consumer")].image} {.spec.containers[?(@.name=="consumer")].volumeMounts[?(@.name=="cache")].mountPath}')" \
    "busybox:1.37 /input"
  check_eq "Pod $P is Ready" "$(jp -n $NS pod $P '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "PVC $P-scratch is Bound with $SCRATCH_SIZE and owned by the pod" \
    "$(jp -n $NS pvc $P-scratch '{.status.phase} {.spec.resources.requests.storage} {.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" \
    "Bound $SCRATCH_SIZE Pod/$P"
  check_eq "/cache is a tmpfs (RAM) in container producer" \
    "$(kc -n $NS exec $P -c producer -- awk '$2=="/cache" {print $3}' /proc/mounts 2>/dev/null)" "tmpfs"
  check_match "consumer sees what producer writes (/input/batch.log)" \
    "$(kc -n $NS exec $P -c consumer -- tail -n 1 /input/batch.log 2>/dev/null)" '[0-9]{2}:[0-9]{2}:[0-9]{2}'
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
