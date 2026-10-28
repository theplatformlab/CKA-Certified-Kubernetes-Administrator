# shellcheck shell=bash
# Q14 — StorageClass and default class
Q_CLUSTER=practice
NS=storage
DEFAULT_ANNOTATION='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'

q_setup() { ensure_ns "$NS"; }

q_check() {
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
