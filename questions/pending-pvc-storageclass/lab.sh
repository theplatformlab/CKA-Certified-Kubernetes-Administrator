# shellcheck shell=bash
# Pod Pending because its PVC references a missing StorageClass. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=reports

lab_params() {
  echo "SIZE=$(pick 1Gi 2Gi 3Gi 5Gi)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: report-data
  namespace: $NS
spec:
  storageClassName: fast-local
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: $SIZE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-writer
  namespace: $NS
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: report-writer
  template:
    metadata:
      labels:
        app: report-writer
    spec:
      containers:
      - name: writer
        image: busybox:1.37
        command: ["sh", "-c", "date >> /reports/runs.log && exec sleep 86400"]
        volumeMounts:
        - name: data
          mountPath: /reports
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: report-data
YAML
}

lab_check() {
  check_gate "PVC report-data is Bound" test "$(jp -n $NS pvc report-data '{.status.phase}')" = "Bound"
  check_eq "PVC report-data uses StorageClass standard" "$(jp -n $NS pvc report-data '{.spec.storageClassName}')" "standard"
  check_eq "PVC report-data still requests $SIZE ReadWriteOnce" \
    "$(jp -n $NS pvc report-data '{.spec.resources.requests.storage} {.spec.accessModes[*]}')" "$SIZE ReadWriteOnce"
  check_not "No StorageClass fast-local was created" exists sc fast-local
  check_eq "Deployment report-writer still mounts claim report-data at /reports" \
    "$(jp -n $NS deploy report-writer '{.spec.template.spec.volumes[0].persistentVolumeClaim.claimName} {.spec.template.spec.containers[0].volumeMounts[0].mountPath}')" \
    "report-data /reports"
  check_eq "Deployment report-writer has 1 ready replica" "$(jp -n $NS deploy report-writer '{.status.readyReplicas}')" "1"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc delete storageclass fast-local --ignore-not-found
}
