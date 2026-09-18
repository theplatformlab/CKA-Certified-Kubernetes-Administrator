# Exercise 12 — Storage: PV, PVC, and StorageClass

> Related: [PV skeleton](../../skeletons/pv.yaml) | [PVC skeleton](../../skeletons/pvc.yaml) | [StorageClass skeleton](../../skeletons/storageclass.yaml) | [README — Storage](../../README.md#domain-1--storage-10)

Create PersistentVolumes, PersistentVolumeClaims, and mount them into pods. This covers static provisioning and StorageClass basics. You'll verify not just that the PVC binds, but that a consuming Pod can successfully schedule and use the storage.

## Tasks

1. Create a namespace called `exercise-12`
2. Create a PersistentVolume named `my-pv` with:
   - Capacity: 1Gi
   - AccessMode: ReadWriteOnce
   - StorageClass: `manual`
   - hostPath: `/data/exercise-12`
   - Reclaim policy: Retain
3. Create a PersistentVolumeClaim named `my-pvc` in namespace `exercise-12`:
   - Request: 500Mi
   - AccessMode: ReadWriteOnce
   - StorageClass: `manual`
4. Create a pod named `storage-consumer` that mounts `my-pvc` at `/data`
5. Verify:
   - The PVC is **Bound** to the PV
   - The Pod is **Running** (not stuck Pending) — the consumer Pod proves the storage is actually usable
6. Write a test file inside the mounted volume from the Pod
7. Delete the pod, create a new pod with the same PVC, and verify the file persists
8. Delete the PVC and check PV status (should be **Released**, not Available, because policy is Retain)

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- PV is cluster-scoped (no namespace). PVC is namespace-scoped.
- The PVC binds to a PV if: capacity >= request AND accessMode matches AND storageClass matches
- **Pod scheduling:** A Pod that mounts a PVC stays Pending until the PVC is Bound. If the PVC never binds, the Pod never runs. This is how you verify end-to-end storage provisioning works.
- With `Retain`, deleting the PVC releases the PV but doesn't delete the data on disk
- With `Delete`, deleting the PVC deletes the PV and its data
- Use `k get pv`, `k get pvc -n <ns>`, and `k get pods -n <ns>` to verify all three: PV exists, PVC is Bound, Pod is Running
- **Namespace enforcement:** `my-pvc` is in `exercise-12`, so `storage-consumer` Pod must also be in `exercise-12`. Reference the PVC by name (`claimName: my-pvc`); the Pod will look for it in the same namespace.

</details>

## Diagnostic: PVC Stuck in Pending (Reddit Feedback)

**Common Issue:** PVC stays `Pending` even though PV exists. Here's the decision tree:

```
1. Is PV available?
   └─ k get pv
   └─ If no PV: CREATE it first
   └─ If PV status is "Bound" → someone else claimed it, create a new PV

2. Does PVC request match PV capacity?
   └─ k describe pvc <name>
   └─ Look for "Insufficient capacity" message
   └─ PV capacity MUST be >= PVC request
   └─ If not: create bigger PV or smaller PVC request

3. Do accessModes match exactly?
   └─ k describe pv <pv-name> → shows accessModes
   └─ k describe pvc <pvc-name> → shows accessModes requested
   └─ "ReadWriteOnce" ≠ "ReadWriteMany" → must match exactly
   └─ If not: fix accessModes

4. Does storageClassName match?
   └─ k get pv <pv> → shows storageClassName
   └─ k get pvc <pvc> → shows storageClassName
   └─ BOTH must say "manual" (or same class name)
   └─ Easy to miss: one says "manual", other says "standard"
   └─ If not: make them match

5. Problems still persist?
   └─ k get events -n <ns> → look for PVC event errors
   └─ Check node: does hostPath directory exist? `ssh node; ls /data/exercise-12`
   └─ Check RBAC: does kubelet have permissions? (rare but possible)
```

**ReclaimPolicy Explained (Reddit: Often Confused)**
- `Retain`: After PVC deleted, PV becomes Released (data stays on disk)
  - Must manually delete PV or re-use it
  - Safer for static provisioning
- `Delete`: After PVC deleted, PV is automatically deleted (data destroyed)
  - Use for dynamic provisioning (StorageClass)
  - Risky for exercise: if you delete PVC, PV disappears

**Access Modes Explained (Reddit: Candidates mix these up)**
- `ReadWriteOnce (RWO)`: A volume can be mounted as read-write by a single node at a time. Multiple pods on the same node may share the same volume read-write, but it cannot be mounted read-write on two different nodes at the same time.
- `ReadWriteOncePod (RWOP)`: The volume can be mounted as read-write by only one pod, regardless of node. This is the pod-scoped exclusivity mode.
- `ReadOnlyMany (ROX)`: Multiple Pods can mount (read-only).
- `ReadWriteMany (RWX)`: Multiple Pods can mount (read+write). Requires network storage (NFS, etc).
- **Common exam mistake:** Confusing `ReadWriteOnce` with `ReadWriteOncePod`. `RWO` is node-scoped, not pod-scoped. `RWOP` is the mode that restricts access to a single pod.
- **Test this:** On the same node, two Pods can often read/write the same `ReadWriteOnce` PVC. If you need strict single-pod write access, use `ReadWriteOncePod` instead.

> **CKA note:** For Kubernetes 1.36+, the exam-safe wording is: `RWO` = one node, `RWOP` = one pod.

> **Storage Binding Requires Name Exactness**
> 
> PVC stuck in Pending for 10 minutes. I checked accessModes, checked capacity, everything matched. Turned out: my PV had `storageClassName: manual` and my PVC had `storageClassName: standard`. One word difference, no error message — just Pending forever. Always triple-check `storageClassName` matches exactly between PV and PVC. Same goes for `accessModes` — if PV is `ReadWriteMany` but PVC requests `ReadWriteOnce`, they won't bind.

> **Namespace Mismatch Breaks Pod-PVC Connection**
>
> PVC was in `default` namespace, Pod was in `exercise-12`. The PVC was Bound to the PV, so I thought everything worked. But when I created the Pod in `exercise-12`, it stayed Pending. Reason: the Pod couldn't find the PVC because they're in different namespaces. PVC and consuming Pod MUST be in the same namespace. The Pod correctly finds the PVC by name (`claimName: my-pvc`) only if they share a namespace.

> **Pod Readiness Proves Storage Works**
>
> "PVC is Bound" looks good on paper, but until you attach a Pod and it becomes Running, you haven't proven the storage actually works. A Pod staying Pending means either: (a) the PVC isn't Bound, (b) the hostPath doesn't exist on the node, (c) permissions are wrong, or (d) scheduling constraints prevent placement. Always verify the consumer Pod reaches Running state — that's your real test.

> **hostPath Directory Must Exist on Node**
>
> Created PV with `hostPath: /data/exercise-12` but forgot to `mkdir -p /data/exercise-12` on the node. Pod stayed Pending. The node has to have the backing directory, and if running on a multi-node cluster, the Pod might land on a node that doesn't have it. Consider this when designing storage tests.

## Verify + Cleanup

```bash
# Step 1: Verify PV exists and is available (pre-PVC-binding)
k get pv my-pv

# Step 2: Verify PVC is BOUND (this proves the binding succeeded)
k get pvc my-pvc -n exercise-12
# Status should be: Bound

# Step 3: Verify Pod is RUNNING (this proves end-to-end storage works)
k get pods -n exercise-12
# storage-consumer should be Ready 1/1 and Running

# Step 4: Verify file persists after pod recreation
k exec storage-consumer -n exercise-12 -- cat /data/test.txt

# Step 5: After deleting PVC, PV status should be Released (not Available)
k delete pvc my-pvc -n exercise-12
k get pv my-pv
# Status should be: Released

# Cleanup
k delete ns exercise-12
k delete pv my-pv
sudo rm -rf /data/exercise-12
```

<details>
<summary>Solution</summary>

```bash
k create ns exercise-12

# Create the host directory (on the node)
sudo mkdir -p /data/exercise-12
```

```yaml
# pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /data/exercise-12
```

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
  namespace: exercise-12
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  storageClassName: manual
```

```yaml
# pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-consumer
  namespace: exercise-12
spec:
  containers:
  - name: consumer
    image: busybox:1.35
    command: ['sleep', '3600']  # Keeps pod running
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

```bash
k apply -f pv.yaml
k apply -f pvc.yaml

# Verify PVC is Bound BEFORE creating the Pod
k get pvc my-pvc -n exercise-12
# STATUS should be Bound

# Create the consumer Pod
k apply -f pod.yaml

# Wait for Pod to be Running (proves PVC is usable)
k get pods -n exercise-12 storage-consumer
# Should show: storage-consumer 1/1 Running

# Write a test file
k exec storage-consumer -n exercise-12 -- touch /data/test.txt
k exec storage-consumer -n exercise-12 -- sh -c 'echo "data persists" > /data/test.txt'

# Delete and recreate pod to verify persistence
k delete pod storage-consumer -n exercise-12
k apply -f pod.yaml

# Verify file persists
k exec storage-consumer -n exercise-12 -- cat /data/test.txt
# Output: data persists

# Test reclaim policy
k delete pod storage-consumer -n exercise-12
k delete pvc my-pvc -n exercise-12
k get pv my-pv
# STATUS should be Released (not Available) because policy is Retain
```

</details>
