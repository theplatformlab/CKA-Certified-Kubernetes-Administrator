# shellcheck shell=bash
# Static PersistentVolume. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=databases

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-app
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db-app
  template:
    metadata:
      labels:
        app: db-app
    spec:
      containers:
      - name: app
        image: busybox:1.37
        command: ["sleep", "86400"]
EOF
}

lab_check() {
  check_gate "PVC db-pvc exists" exists -n $NS pvc db-pvc
  check_eq "StorageClass fast-ssd: provisioner, binding mode, reclaim policy" \
    "$(jp sc fast-ssd '{.provisioner} {.volumeBindingMode} {.reclaimPolicy}')" \
    "kubernetes.io/no-provisioner WaitForFirstConsumer Retain"
  check_eq "PV db-pv: 5Gi ReadWriteMany fast-ssd Retain" \
    "$(jp pv db-pv '{.spec.capacity.storage} {.spec.accessModes[*]} {.spec.storageClassName} {.spec.persistentVolumeReclaimPolicy}')" \
    "5Gi ReadWriteMany fast-ssd Retain"
  check_eq "PV db-pv uses hostPath /mnt/data/db (DirectoryOrCreate)" \
    "$(jp pv db-pv '{.spec.hostPath.path} {.spec.hostPath.type}')" "/mnt/data/db DirectoryOrCreate"
  check_eq "PVC db-pvc requests 5Gi ReadWriteMany from fast-ssd" \
    "$(jp -n $NS pvc db-pvc '{.spec.resources.requests.storage} {.spec.accessModes[*]} {.spec.storageClassName}')" \
    "5Gi ReadWriteMany fast-ssd"
  check_eq "PVC db-pvc is Bound to db-pv" "$(jp -n $NS pvc db-pvc '{.status.phase} {.spec.volumeName}')" "Bound db-pv"
  local vol
  vol="$(jp -n $NS deploy db-app '{.spec.template.spec.volumes[?(@.persistentVolumeClaim.claimName=="db-pvc")].name}')"
  check_match "Deployment db-app has a volume for claim db-pvc" "$vol" '.+'
  check_eq "The claim is mounted at /data" \
    "$(jp -n $NS deploy db-app "{.spec.template.spec.containers[0].volumeMounts[?(@.name==\"${vol:-none}\")].mountPath}")" "/data"
  check_eq "Deployment db-app is Ready" "$(jp -n $NS deploy db-app '{.status.readyReplicas}')" "1"
}

lab_cleanup() {
  kc -n "$NS" delete deploy db-app pvc db-pvc --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kc delete pv db-pv --ignore-not-found >/dev/null 2>&1 || true
  kc delete storageclass fast-ssd --ignore-not-found >/dev/null 2>&1 || true
}
