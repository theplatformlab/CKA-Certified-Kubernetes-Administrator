# shellcheck shell=bash
# StorageClass and default class. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=storage
DEFAULT_ANNOTATION='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  check_gate "StorageClass local-ssd exists" exists sc local-ssd
  check_eq "local-ssd: provisioner, reclaim policy, binding mode" \
    "$(jp sc local-ssd '{.provisioner} {.reclaimPolicy} {.volumeBindingMode}')" \
    "rancher.io/local-path Retain WaitForFirstConsumer"
  check_eq "local-ssd is the default StorageClass" "$(jp sc local-ssd "$DEFAULT_ANNOTATION")" "true"
  check_not "standard is no longer a default StorageClass" test "$(jp sc standard "$DEFAULT_ANNOTATION")" = "true"
  check_eq "PVC data-pvc: 2Gi ReadWriteOnce, got local-ssd as default class" \
    "$(jp -n $NS pvc data-pvc '{.spec.resources.requests.storage} {.spec.accessModes[0]} {.spec.storageClassName}')" \
    "2Gi ReadWriteOnce local-ssd"
  check_eq "PVC data-pvc is Bound" "$(jp -n $NS pvc data-pvc '{.status.phase}')" "Bound"
  check_eq "Pod data-pod mounts data-pvc at /usr/share/nginx/html" \
    "$(kc -n $NS get pod data-pod -o json 2>/dev/null | jq -r '.spec as $s | $s.volumes[] | select(.persistentVolumeClaim.claimName=="data-pvc") | .name as $v | $s.containers[0].volumeMounts[] | select(.name==$v) | .mountPath')" \
    "/usr/share/nginx/html"
  check_eq "Pod data-pod is Running" "$(jp -n $NS pod data-pod '{.status.phase}')" "Running"
}

lab_cleanup() {
  kc annotate storageclass standard storageclass.kubernetes.io/is-default-class=true --overwrite >/dev/null 2>&1 || true
  kc -n "$NS" delete pod data-pod pvc data-pvc --ignore-not-found >/dev/null 2>&1 || true
  # local-ssd has reclaimPolicy Retain: remove its released volumes explicitly.
  kc get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName == "local-ssd") | .metadata.name' \
    | xargs -r kubectl --context "$CTX" delete pv --ignore-not-found >/dev/null 2>&1 || true
  kc delete storageclass local-ssd --ignore-not-found >/dev/null 2>&1 || true
}
