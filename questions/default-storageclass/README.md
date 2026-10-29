# StorageClass and default class

**Context:** `kubectl config use-context {{CONTEXT}}`

1. Create a StorageClass named `local-ssd`:
   - provisioner `rancher.io/local-path`
   - `reclaimPolicy: Retain`
   - `volumeBindingMode: WaitForFirstConsumer`
2. Make `local-ssd` the cluster's default StorageClass. `standard` must no longer be the default.
3. In namespace `storage`, create a PVC named `data-pvc` that requests `2Gi` with `ReadWriteOnce`, without specifying a StorageClass.
4. In namespace `storage`, create a pod named `data-pod` with image `nginx:1.28` that mounts `data-pvc` at `/usr/share/nginx/html`. The PVC must be `Bound`.

## Hints

- The default class is set by the annotation `storageclass.kubernetes.io/is-default-class: "true"`.
- Remove the annotation (or set it to false) on the old default class.
- The default is filled in when a PVC is created: create the PVC after switching the default.

## Solution

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

```bash
k config use-context {{CONTEXT}}
k apply -f sc.yaml
k patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
k get sc                     # only local-ssd shows (default)
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
  namespace: storage
spec:
  containers:
  - name: web
    image: nginx:1.28
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```

Order matters. The default class is filled into a PVC when it is created, so a PVC created before you switch the default keeps `standard`. With two defaults, Kubernetes uses the newest one, but don't rely on that: remove the old default explicitly.
