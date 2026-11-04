# Static PersistentVolume

**Context:** `kubectl config use-context {{CONTEXT}}`

The Deployment `db-app` in namespace `databases` needs shared storage.

1. Create a StorageClass named `fast-ssd` with provisioner `kubernetes.io/no-provisioner`, `volumeBindingMode: WaitForFirstConsumer` and `reclaimPolicy: Retain`.
2. Create a PersistentVolume named `db-pv`:
   - capacity `5Gi`
   - access mode `ReadWriteMany`
   - StorageClass `fast-ssd`
   - reclaim policy `Retain`
   - `hostPath` `/mnt/data/db`, type `DirectoryOrCreate`
3. Create a PersistentVolumeClaim named `db-pvc` in namespace `databases`. It must request `5Gi` with `ReadWriteMany` from StorageClass `fast-ssd`.
4. Update Deployment `db-app` to mount the claim at `/data`. The Deployment must be Ready and the PVC `Bound` to `db-pv`.

## Hints

- A StorageClass with `kubernetes.io/no-provisioner` never creates volumes: you create the PV yourself.
- PV and PVC must match on storageClassName, accessModes and size.
- With WaitForFirstConsumer the PVC stays Pending until a pod uses it. Add the volume to the Deployment's pod template.

## Solution

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: db-pv
spec:
  capacity:
    storage: 5Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd
  hostPath:
    path: /mnt/data/db
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-pvc
  namespace: databases
spec:
  accessModes: [ReadWriteMany]
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 5Gi
```

```bash
k config use-context {{CONTEXT}}
k apply -f q4.yaml
k -n databases edit deploy db-app
```

```yaml
    spec:
      containers:
      - name: app
        # ...
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: db-pvc
```

With `WaitForFirstConsumer`, the PVC stays `Pending` until a pod uses it. That is expected, not an error. hostPath volumes don't enforce access modes, so RWX works here. In production you would use NFS or CephFS for real RWX.
