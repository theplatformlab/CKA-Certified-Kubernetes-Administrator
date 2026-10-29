# Exercise 25 — Storage with WaitForFirstConsumer Binding

> Related: [Storage skeleton](../../skeletons/storageclass.yaml) | [README — Storage](../../README.md#domain-6--storage-10)

Create a StorageClass with `WaitForFirstConsumer` binding mode, and understand why PVCs remain Pending until a pod actually uses them.

## Tasks

Work in namespace `exercise-25` (`./scripts/lab.sh setup 25` creates it and prepares the disk). The "local disk" is the directory `/mnt/disks/vol1` on node `cka-practice-worker`. A `local` PV needs its path to exist on the node.

1. Create a StorageClass named `local-storage` with:
   - Provisioner: `kubernetes.io/no-provisioner` (local volumes)
   - Binding mode: `WaitForFirstConsumer`
2. Create a PersistentVolume (PV) with:
   - Name: `local-pv-1`
   - Size: 1Gi
   - AccessMode: ReadWriteOnce
   - StorageClassName: `local-storage`
   - Local path: `/mnt/disks/vol1`
   - nodeAffinity: `kubernetes.io/hostname` In `cka-practice-worker` (required for `local` volumes)
3. Create a PersistentVolumeClaim (PVC) in `exercise-25` with:
   - Name: `local-pvc`
   - Size: 1Gi, AccessMode ReadWriteOnce
   - StorageClassName: `local-storage` (the cluster's default class is `standard`, so set it explicitly)
4. Observe: PVC remains Pending (not Bound) — WHY?
5. Create a Pod `app-pod` in `exercise-25` that uses the PVC:
   - Image: `busybox:1.36`, command `sleep 3600`
   - Mount PVC at `/data`
6. Observe: Now PVC transitions to Bound
   - Pod schedules on `cka-practice-worker`, the node where the PV exists
7. Verify data persistence: from the pod, write `hello` into `/data/test.txt` and find it in `/mnt/disks/vol1` on the node

Validate with `./scripts/lab.sh check 25`.

## Key Learning

- `WaitForFirstConsumer` = PVC stays Pending until a pod needs it
- Binding is deferred to allow node affinity scheduling
- Useful for local storage where PV is tied to a specific node
- Exam tests understanding of binding modes and their tradeoffs

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- PVC should show `Pending` initially, not `Bound`
- Once pod is created using PVC, PVC transitions to `Bound`
- Pod scheduling respects the PV node affinity
- `k get pvc -w` to watch the status change

</details>

## What tripped me up

> I created the PVC and expected it to be Bound immediately. It stayed Pending and I thought something was wrong. Turns out `WaitForFirstConsumer` is by design — it doesn't bind until a consumer appears. On the exam, if you see a PVC stuck in Pending, check the StorageClass binding mode. It might be intentional, not a bug. The pod has to request the PVC first, then binding happens. If the pod and PV are on different nodes, the pod won't schedule.
>
> Also: don't forget the PV needs a valid `local` path on the node, or uses a real provisioner (cloud). Without a provisioner, `WaitForFirstConsumer` + local storage is commonly tested.

## Verify

```bash
./scripts/lab.sh check 25
```

Manual checks:

```bash
# Initially: PVC should be Pending
k get pvc -n exercise-25

# After pod creation: PVC should be Bound
k get pvc -n exercise-25

# Pod should be Running
k get pod -n exercise-25

# Pod runs on the PV's node
k get pod app-pod -n exercise-25 -o wide

# Read the test file back, in the pod and on the node
k exec app-pod -n exercise-25 -- cat /data/test.txt
docker exec cka-practice-worker cat /mnt/disks/vol1/test.txt
```

## Cleanup

```bash
./scripts/lab.sh cleanup 25     # namespace, PV, StorageClass and /mnt/disks on the node
```

<details>
<summary>Solution</summary>

```bash
kn exercise-25

# Create StorageClass with WaitForFirstConsumer
cat <<EOF | k apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

# Create PersistentVolume
cat <<EOF | k apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-1
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  local:
    path: /mnt/disks/vol1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - cka-practice-worker
EOF

# Verify PV created
k get pv

# Create PVC — will be Pending
cat <<EOF | k apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-pvc
  namespace: exercise-25
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: 1Gi
EOF

# Check status — should be Pending
k get pvc

# Create Pod using PVC
cat <<EOF | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  namespace: exercise-25
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: local-pvc
EOF

# Now PVC should be Bound
k get pvc -w
# Watch it change from Pending to Bound

# Verify pod is running on cka-practice-worker
k get pod -o wide

# Test write
k exec app-pod -n exercise-25 -- sh -c 'echo "hello" > /data/test.txt'
k exec app-pod -n exercise-25 -- cat /data/test.txt
docker exec cka-practice-worker cat /mnt/disks/vol1/test.txt   # same file on the node
```

</details>
