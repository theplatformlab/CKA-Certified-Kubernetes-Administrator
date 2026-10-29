# shellcheck shell=bash
# Exercise 25 — StorageClass with WaitForFirstConsumer and a local PV. Sourced by scripts/lab.sh.
# Setup prepares the "local disk" directory on the first worker node.
LAB_CLUSTER=practice
NS=exercise-25
DISK=/mnt/disks/vol1

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  node_exec "$(worker_node 1)" "mkdir -p $DISK"
  echo "  Local disk directory $DISK exists on $(worker_node 1)."
}

lab_check() {
  local node pv='{.spec.capacity.storage} {.spec.accessModes[0]} {.spec.storageClassName}'
  node="$(worker_node 1)"
  check_eq "StorageClass local-storage uses provisioner kubernetes.io/no-provisioner" \
    "$(jp storageclass local-storage '{.provisioner}')" "kubernetes.io/no-provisioner"
  check_eq "StorageClass local-storage has volumeBindingMode WaitForFirstConsumer" \
    "$(jp storageclass local-storage '{.volumeBindingMode}')" "WaitForFirstConsumer"

  check_eq "PV local-pv-1: 1Gi, ReadWriteOnce, StorageClass local-storage" \
    "$(jp pv local-pv-1 "$pv")" "1Gi ReadWriteOnce local-storage"
  check_eq "PV local-pv-1 is a local volume at $DISK" "$(jp pv local-pv-1 '{.spec.local.path}')" "$DISK"
  check_eq "PV local-pv-1 has nodeAffinity kubernetes.io/hostname=$node" \
    "$(jp pv local-pv-1 '{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]}')" \
    "$node"

  check_eq "PVC local-pvc requests 1Gi from StorageClass local-storage" \
    "$(jp -n $NS pvc local-pvc '{.spec.resources.requests.storage} {.spec.storageClassName}')" "1Gi local-storage"
  check_eq "PVC local-pvc is Bound to local-pv-1" \
    "$(jp -n $NS pvc local-pvc '{.status.phase} {.spec.volumeName}')" "Bound local-pv-1"

  check_eq "Pod app-pod runs busybox:1.36 and is Running" \
    "$(jp -n $NS pod app-pod '{.spec.containers[0].image} {.status.phase}')" "busybox:1.36 Running"
  check_eq "app-pod was scheduled to $node (where the PV lives)" "$(jp -n $NS pod app-pod '{.spec.nodeName}')" "$node"
  check_eq "app-pod mounts PVC local-pvc at /data" \
    "$(jp -n $NS pod app-pod '{.spec.volumes[?(@.persistentVolumeClaim.claimName=="local-pvc")].name}:{.spec.containers[0].volumeMounts[?(@.mountPath=="/data")].name}' | awk -F: '$1 != "" && $1 == $2 {print "ok"}')" "ok"
  check_eq "$DISK/test.txt on $node contains 'hello' (written through the pod)" \
    "$(node_exec "$node" "cat $DISK/test.txt" 2>/dev/null)" "hello"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc delete pv local-pv-1 --ignore-not-found --wait=false
  kc delete storageclass local-storage --ignore-not-found
  node_exec "$(worker_node 1)" "rm -rf /mnt/disks" 2>/dev/null || true
}
