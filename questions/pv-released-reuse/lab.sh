# shellcheck shell=bash
# Reuse a Released PersistentVolume (Retain). Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=archive
PV=archive-pv
DIR=/var/local/archive-pv

lab_params() {
  echo "PVC=$(pick archive-data archive-restore records-claim)"
  echo "TOKEN=$(rand_suffix 10)"
}

lab_setup() {
  local node; node="$(worker_node 1)"
  # Start from scratch: a Released PV can't simply be re-applied.
  kc delete namespace "$NS" --ignore-not-found --wait=true >/dev/null
  kc delete pv "$PV" --ignore-not-found --wait=true >/dev/null
  node_exec "$node" "rm -rf $DIR"
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV
spec:
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive
  hostPath:
    path: $DIR
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [$node]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-old
  namespace: $NS
spec:
  storageClassName: archive
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: archive-writer
  namespace: $NS
spec:
  restartPolicy: Never
  containers:
  - name: writer
    image: busybox:1.37
    command: ["sh", "-c", "echo 'archived records $TOKEN' > /data/records.txt"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: archive-old
YAML
  kc -n $NS wait --for=jsonpath='{.status.phase}'=Succeeded pod/archive-writer --timeout=180s >/dev/null
  kc -n $NS delete pod archive-writer --wait=true >/dev/null
  kc -n $NS delete pvc archive-old --wait=true >/dev/null
  kc wait --for=jsonpath='{.status.phase}'=Released pv/$PV --timeout=60s >/dev/null
  # Remember the PV's identity to detect a delete + recreate.
  kc annotate namespace "$NS" "lab.cka/pv-uid=$(jp pv $PV '{.metadata.uid}')" --overwrite >/dev/null
}

lab_check() {
  check_gate "PV $PV is Bound" test "$(jp pv $PV '{.status.phase}')" = "Bound"
  check_eq "PV $PV is the original one (not recreated)" \
    "$(jp pv $PV '{.metadata.uid}')" "$(jp namespace $NS '{.metadata.annotations.lab\.cka/pv-uid}')"
  check_eq "PV $PV keeps reclaim policy Retain" "$(jp pv $PV '{.spec.persistentVolumeReclaimPolicy}')" "Retain"
  check_eq "PV $PV is bound to $NS/$PVC" "$(jp pv $PV '{.spec.claimRef.namespace}/{.spec.claimRef.name}')" "$NS/$PVC"
  check_eq "PVC $PVC is Bound to $PV (1Gi ReadWriteOnce)" \
    "$(jp -n $NS pvc "$PVC" '{.status.phase} {.spec.volumeName} {.spec.resources.requests.storage} {.spec.accessModes[*]}')" \
    "Bound $PV 1Gi ReadWriteOnce"
  check_eq "Pod archive-reader is Running with claim $PVC at /data" \
    "$(jp -n $NS pod archive-reader '{.status.phase} {.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName} {.spec.containers[0].volumeMounts[0].mountPath}')" \
    "Running $PVC /data"
  check_contains "The old data is still there (/data/records.txt)" \
    "$(kc -n $NS exec archive-reader -- cat /data/records.txt 2>/dev/null)" "archived records $TOKEN"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=true >/dev/null
  kc delete pv "$PV" --ignore-not-found
  node_exec "$(worker_node 1)" "rm -rf $DIR"
}
