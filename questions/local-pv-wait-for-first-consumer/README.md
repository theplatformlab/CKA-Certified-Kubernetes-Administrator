# Local PersistentVolume with WaitForFirstConsumer

**Context:** `kubectl config use-context {{CONTEXT}}`

Node `{{NODE_W1}}` has a local disk mounted at `/mnt/disks/{{DISK}}`.

1. Create a StorageClass named `local-storage` with provisioner `kubernetes.io/no-provisioner` and volume binding mode `WaitForFirstConsumer`.
2. Create a PersistentVolume named `local-pv-1`: capacity `{{SIZE}}`, access mode `ReadWriteOnce`, StorageClass `local-storage`, a `local` volume with path `/mnt/disks/{{DISK}}`. It can only be used on node `{{NODE_W1}}`.
3. In namespace `local-disks`, create a PersistentVolumeClaim named `local-pvc` that requests `{{SIZE}}` with `ReadWriteOnce` from StorageClass `local-storage`.
4. In namespace `local-disks`, create a Pod named `app-pod` (image `busybox:1.37`, command `sleep 3600`) that mounts `local-pvc` at `/data`. Through the pod, write `hello` into `/data/test.txt`.

## Hints

- A `local` PersistentVolume requires `spec.nodeAffinity` (`kubernetes.io/hostname`); the API server rejects it without one.
- With `WaitForFirstConsumer` the PVC stays `Pending` until a pod uses it. That is expected, not an error.
- The cluster's default StorageClass is `standard`, so the PVC has to name `local-storage` explicitly.

## Solution

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-1
spec:
  capacity:
    storage: {{SIZE}}
  accessModes:
  - ReadWriteOnce
  storageClassName: local-storage
  local:
    path: /mnt/disks/{{DISK}}
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - {{NODE_W1}}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: local-pvc
  namespace: local-disks
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: local-storage
  resources:
    requests:
      storage: {{SIZE}}
---
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  namespace: local-disks
spec:
  containers:
  - name: app
    image: busybox:1.37
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: local-pvc
```

```bash
k apply -f local.yaml
k -n local-disks get pvc local-pvc        # Bound once app-pod is scheduled
k -n local-disks get pod app-pod -o wide  # runs on {{NODE_W1}}
k -n local-disks exec app-pod -- sh -c 'echo hello > /data/test.txt'
```

The scheduler places `app-pod` on `{{NODE_W1}}` because the PV's node affinity allows no other node; only then is the PVC bound.

## Pitfalls

- The PVC is not `Bound` right away, and that is not a fault: with `WaitForFirstConsumer` binding waits for the first pod, so the volume's node can be taken into account.
- A `local` volume's directory must already exist on the node; the pod stays in `ContainerCreating` otherwise.
