# emptyDir in memory and a generic ephemeral volume

**Context:** `kubectl config use-context {{CONTEXT}}`

Create a pod `etl-worker` in namespace `scratch-space` with two volumes and two containers:

- volume `cache`: an `emptyDir` kept in memory (tmpfs), limited to `{{CACHE_SIZE}}`
- volume `scratch`: a **generic ephemeral volume**, i.e. a PVC created and deleted together with the pod, with StorageClass `standard`, access mode `ReadWriteOnce` and `{{SCRATCH_SIZE}}` of storage
- container `producer`, image `busybox:1.37`, command `sh -c 'while true; do date >> /cache/batch.log; sleep 5; done'`, mounts `cache` at `/cache` and `scratch` at `/scratch`
- container `consumer`, image `busybox:1.37`, command `sh -c 'tail -F /input/batch.log'`, mounts `cache` at `/input`

The pod must be Running and Ready, and the consumer must see the producer's file.

## Hints

- `k explain pod.spec.volumes.emptyDir`: `medium: Memory`, `sizeLimit`.
- `k explain pod.spec.volumes.ephemeral.volumeClaimTemplate`: its `spec` is a normal PVC spec. Kubernetes names the PVC `<pod>-<volume>`.
- `standard` binds `WaitForFirstConsumer`: the PVC stays Pending until the pod is scheduled, then gets provisioned.

## Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: etl-worker
  namespace: scratch-space
spec:
  containers:
  - name: producer
    image: busybox:1.37
    command: ["sh", "-c", "while true; do date >> /cache/batch.log; sleep 5; done"]
    volumeMounts:
    - name: cache
      mountPath: /cache
    - name: scratch
      mountPath: /scratch
  - name: consumer
    image: busybox:1.37
    command: ["sh", "-c", "tail -F /input/batch.log"]
    volumeMounts:
    - name: cache
      mountPath: /input
  volumes:
  - name: cache
    emptyDir:
      medium: Memory
      sizeLimit: {{CACHE_SIZE}}
  - name: scratch
    ephemeral:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: {{SCRATCH_SIZE}}
```

```bash
k config use-context {{CONTEXT}}
k apply -f etl-worker.yaml
k -n scratch-space get pod,pvc                 # PVC etl-worker-scratch Bound
k -n scratch-space exec etl-worker -c producer -- df -h /cache /scratch   # tmpfs, local-path disk
k -n scratch-space logs etl-worker -c consumer
```

Both are ephemeral: they live and die with the pod. The emptyDir lives in the node's RAM (and counts against the containers' memory limit), the generic ephemeral volume is a real PVC from a StorageClass, so it can be large, use any CSI driver and be deleted automatically with the pod (the PVC's owner is the pod). That's the difference to a `persistentVolumeClaim` volume, whose PVC you create and delete yourself.
