# Reuse a Released PersistentVolume

**Context:** `kubectl config use-context {{CONTEXT}}`

The PersistentVolumeClaim of an old archive application in namespace `archive` was deleted by mistake. Its PersistentVolume `archive-pv` still holds the data, but it is not available for new claims.

1. Make `archive-pv` usable again. Do not delete or recreate it, and keep its data and its reclaim policy.
2. Create a PersistentVolumeClaim named `{{PVC}}` in namespace `archive` that requests `1Gi` with access mode `ReadWriteOnce` and binds to `archive-pv`.
3. Create a Pod named `archive-reader` in namespace `archive` (image `busybox:1.37`, command `sleep 3600`) that mounts the claim at `/data`.

The file `/data/records.txt` must be readable in the pod.

## Hints

- `k get pv archive-pv`: what is its `STATUS`, and which claim does it still remember (`CLAIM`)?
- A `Released` volume keeps its `spec.claimRef` to the deleted claim and is never bound again until that reference is removed.
- `k patch pv archive-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'`. The new claim must ask for the PV's `storageClassName`.

## Solution

```bash
k config use-context {{CONTEXT}}
k get pv archive-pv                  # STATUS Released, CLAIM archive/archive-old, RECLAIM POLICY Retain
k get pv archive-pv -o jsonpath='{.spec.storageClassName}'      # archive

k patch pv archive-pv --type=json -p '[{"op":"remove","path":"/spec/claimRef"}]'
k get pv archive-pv                  # Available
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{PVC}}
  namespace: archive
spec:
  storageClassName: archive
  volumeName: archive-pv            # optional, pins the claim to this PV
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: archive-reader
  namespace: archive
spec:
  containers:
  - name: reader
    image: busybox:1.37
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: {{PVC}}
```

```bash
k apply -f archive.yaml
k -n archive exec archive-reader -- cat /data/records.txt
```

With `Retain`, deleting the claim leaves the PV and its data alone, but the PV stays `Released` with the old `claimRef` (including the old claim's UID), so no new claim can bind to it. Removing the `claimRef` makes it `Available` again, and the data is untouched. Without `storageClassName: archive` the claim would get the default class `standard` and a new, empty, dynamically provisioned volume.
