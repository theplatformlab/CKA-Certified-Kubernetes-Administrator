# Pod Pending on its volume

**Context:** `kubectl config use-context {{CONTEXT}}`

The pod of Deployment `report-writer` in namespace `reports` stays `Pending`.

Fix it so that the pod runs:

1. The pod must keep using a PersistentVolumeClaim named `report-data`, mounted at `/reports`.
2. The claim must keep its requested size and access mode, and must use the cluster's StorageClass `standard`.
3. Do not create or modify StorageClasses.

## Hints

- `k -n reports describe pod` and `k -n reports describe pvc report-data`: which object is waiting, and for what?
- `k get storageclass`: does the class the claim asks for exist?
- Most of a PVC's spec (including `storageClassName`) is immutable. Export it, change the class, delete and recreate it.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n reports describe pod -l app=report-writer      # pod has unbound immediate PersistentVolumeClaims
k -n reports describe pvc report-data               # storageclass "fast-local" not found
k get sc                                            # only "standard"

k -n reports get pvc report-data -o yaml > pvc.yaml
# edit pvc.yaml: storageClassName: standard; remove status, uid, resourceVersion, creationTimestamp
k -n reports delete pvc report-data
k apply -f pvc.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: report-data
  namespace: reports
spec:
  storageClassName: standard
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: {{SIZE}}
```

```bash
k -n reports get pvc,pod          # PVC Bound once the pod is scheduled (WaitForFirstConsumer)
```

`k edit pvc` refuses the change: `spec is immutable after creation except resources.requests ...`. The claim has to be recreated. The Pending pod picks up the new claim by name on its next scheduling attempt, no restart needed. (If a claim is used by a running pod, its `kubernetes.io/pvc-protection` finalizer keeps it `Terminating` until the pod is gone.) Creating a StorageClass `fast-local` would also unblock the pod, but the task rules that out.
