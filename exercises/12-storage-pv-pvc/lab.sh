# shellcheck shell=bash
# Exercise 12 — Storage: static PV/PVC with Retain. Sourced by scripts/lab.sh.
# The end state is after task 8: PVC deleted, PV my-pv Released, test file on the node.
LAB_CLUSTER=practice
NS=exercise-12
DIR=/data/exercise-12

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  local node pv='{.spec.capacity.storage} {.spec.accessModes[0]} {.spec.storageClassName} {.spec.persistentVolumeReclaimPolicy}'
  node="$(worker_node 1)"
  check "PersistentVolume my-pv exists" exists pv my-pv
  check_eq "my-pv: 1Gi, ReadWriteOnce, StorageClass manual, reclaim policy Retain" \
    "$(jp pv my-pv "$pv")" "1Gi ReadWriteOnce manual Retain"
  check_eq "my-pv uses hostPath $DIR" "$(jp pv my-pv '{.spec.hostPath.path}')" "$DIR"
  check_eq "my-pv is pinned to node $node (nodeAffinity kubernetes.io/hostname)" \
    "$(jp pv my-pv '{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]}')" \
    "$node"
  check_eq "my-pv was bound to $NS/my-pvc (claimRef)" \
    "$(jp pv my-pv '{.spec.claimRef.namespace}/{.spec.claimRef.name}')" "$NS/my-pvc"
  check_not "PVC my-pvc has been deleted" exists -n $NS pvc my-pvc
  check_eq "my-pv is Released (Retain keeps it after the PVC is gone)" "$(jp pv my-pv '{.status.phase}')" "Released"
  check_eq "$DIR/test.txt on $node contains 'data persists'" \
    "$(node_exec "$node" "cat $DIR/test.txt" 2>/dev/null)" "data persists"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  kc delete pv my-pv --ignore-not-found --wait=false
  local n
  for n in "$(worker_node 1)" "$(worker_node 2)"; do
    node_exec "$n" "rm -rf $DIR" 2>/dev/null || true
  done
}
