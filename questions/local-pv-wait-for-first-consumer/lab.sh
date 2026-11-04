# shellcheck shell=bash
# Local PersistentVolume with WaitForFirstConsumer. Sourced by scripts/lab.sh.
# Setup prepares the "local disk" directory on the first worker node.
LAB_CLUSTER=practice
NS=local-disks

lab_params() {
  echo "DISK=$(pick vol1 vol2 ssd0 ssd1)"
  echo "SIZE=$(pick 1Gi 2Gi 3Gi)"
}

lab_setup() {
  ensure_ns "$NS"
  node_exec "$(worker_node 1)" "mkdir -p /mnt/disks/$DISK"
}

lab_check() {
  local node dir="/mnt/disks/$DISK"
  node="$(worker_node 1)"
  check_gate "StorageClass local-storage exists" exists storageclass local-storage
  check_eq "StorageClass local-storage: kubernetes.io/no-provisioner, WaitForFirstConsumer" \
    "$(jp storageclass local-storage '{.provisioner} {.volumeBindingMode}')" "kubernetes.io/no-provisioner WaitForFirstConsumer"
  check_eq "PV local-pv-1: $SIZE, ReadWriteOnce, StorageClass local-storage" \
    "$(jp pv local-pv-1 '{.spec.capacity.storage} {.spec.accessModes[0]} {.spec.storageClassName}')" "$SIZE ReadWriteOnce local-storage"
  check_eq "PV local-pv-1 is a local volume at $dir" "$(jp pv local-pv-1 '{.spec.local.path}')" "$dir"
  check_eq "PV local-pv-1 is pinned to $node (nodeAffinity kubernetes.io/hostname)" \
    "$(jp pv local-pv-1 '{.spec.nodeAffinity.required.nodeSelectorTerms[*].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[*]}')" "$node"
  check_eq "PVC local-pvc requests $SIZE from local-storage and is Bound to local-pv-1" \
    "$(jp -n $NS pvc local-pvc '{.spec.resources.requests.storage} {.spec.storageClassName} {.status.phase} {.spec.volumeName}')" \
    "$SIZE local-storage Bound local-pv-1"
  check_eq "Pod app-pod (busybox:1.37) is Running on $node" \
    "$(jp -n $NS pod app-pod '{.spec.containers[0].image} {.status.phase} {.spec.nodeName}')" "busybox:1.37 Running $node"
  check_eq "app-pod mounts local-pvc at /data" \
    "$(jp -n $NS pod app-pod '{.spec.volumes[?(@.persistentVolumeClaim.claimName=="local-pvc")].name}:{.spec.containers[0].volumeMounts[?(@.mountPath=="/data")].name}' | awk -F: '$1 != "" && $1 == $2 {print "ok"}')" "ok"
  check_eq "$dir/test.txt on $node contains 'hello'" "$(node_exec "$node" "cat $dir/test.txt" 2>/dev/null)" "hello"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null 2>&1 || true
  kc delete pv local-pv-1 --ignore-not-found --wait=false >/dev/null
  kc delete storageclass local-storage --ignore-not-found >/dev/null
  node_exec "$(worker_node 1)" "rm -rf /mnt/disks" 2>/dev/null || true
}
