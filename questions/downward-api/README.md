# Pod metadata through the Downward API

**Context:** `kubectl config use-context {{CONTEXT}}`

An agent needs to know where it runs without calling the Kubernetes API. Create a pod `reporter` in namespace `fleet-info`:

- image `busybox:1.37`, command `sh -c 'sleep 1d'`, labels `app=reporter` and `team={{TEAM}}`, memory limit `{{MEM}}Mi`
- environment variables filled by Kubernetes:
  - `POD_NAME`: the pod's name
  - `POD_NAMESPACE`: the pod's namespace
  - `NODE_NAME`: the node the pod runs on
  - `POD_IP`: the pod's IP address
  - `MEM_LIMIT_MI`: the container's memory limit in MiB (the plain number, e.g. `{{MEM}}`)
- a volume `podinfo` mounted at `/etc/podinfo` that holds the pod's labels in the file `labels` and its annotations in the file `annotations`

## Hints

- `env[].valueFrom.fieldRef.fieldPath` for pod fields (`metadata.name`, `spec.nodeName`, `status.podIP`, ...).
- `env[].valueFrom.resourceFieldRef` for requests and limits; `divisor: 1Mi` turns bytes into MiB.
- A `downwardAPI` volume has `items` with `path` and `fieldRef` (`metadata.labels`, `metadata.annotations`). Labels and annotations are only available as a volume, not as one env var.

## Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: reporter
  namespace: fleet-info
  labels:
    app: reporter
    team: {{TEAM}}
spec:
  containers:
  - name: reporter
    image: busybox:1.37
    command: ["sh", "-c", "sleep 1d"]
    resources:
      limits:
        memory: {{MEM}}Mi
    env:
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: POD_NAMESPACE
      valueFrom:
        fieldRef:
          fieldPath: metadata.namespace
    - name: NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    - name: POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    - name: MEM_LIMIT_MI
      valueFrom:
        resourceFieldRef:
          containerName: reporter
          resource: limits.memory
          divisor: 1Mi
    volumeMounts:
    - name: podinfo
      mountPath: /etc/podinfo
  volumes:
  - name: podinfo
    downwardAPI:
      items:
      - path: labels
        fieldRef:
          fieldPath: metadata.labels
      - path: annotations
        fieldRef:
          fieldPath: metadata.annotations
```

```bash
k config use-context {{CONTEXT}}
k apply -f reporter.yaml
k -n fleet-info exec reporter -- env | grep -E 'POD_|NODE_|MEM_'
k -n fleet-info exec reporter -- cat /etc/podinfo/labels
```

Env vars are set once at container start; the files in a downwardAPI volume are updated when labels or annotations change (`k label pod reporter tier=x`, then `cat` again). `containerName` is optional inside a container's own env, but required for `resourceFieldRef` in a downwardAPI volume.
