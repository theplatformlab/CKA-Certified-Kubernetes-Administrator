# Native sidecar container

**Context:** `kubectl config use-context {{CONTEXT}}`

Create a pod named `app-with-logger` in namespace `logging`:

- main container `nginx`, image `nginx:1.28`, which mounts an `emptyDir` volume named `logs` at `/var/log/nginx`
- a sidecar named `logger`, image `busybox:1.37`, implemented as a native sidecar (an init container that keeps running), with command `sh -c 'tail -F /logs/access.log'` and the same `logs` volume mounted at `/logs`

Requests to nginx must show up in the logs of container `logger`.

## Hints

- A native sidecar is an entry in `initContainers` with `restartPolicy: Always`.
- Both containers mount the same emptyDir volume, each at its own path.
- Mounting the emptyDir over `/var/log/nginx` hides the image's stdout symlinks, so nginx writes real files.

## Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-logger
  namespace: logging
spec:
  initContainers:
  - name: logger
    image: busybox:1.37
    restartPolicy: Always          # this makes it a native sidecar
    command: ["sh", "-c", "tail -F /logs/access.log"]
    volumeMounts:
    - name: logs
      mountPath: /logs
  containers:
  - name: nginx
    image: nginx:1.28
    volumeMounts:
    - name: logs
      mountPath: /var/log/nginx
  volumes:
  - name: logs
    emptyDir: {}
```

```bash
k -n logging exec app-with-logger -c nginx -- curl -s localhost >/dev/null
k -n logging logs app-with-logger -c logger
```

The nginx image links `access.log` to stdout. Mounting the emptyDir over `/var/log/nginx` hides that symlink, so nginx writes a real file the sidecar can tail. `tail -F` (capital F) keeps retrying until the file exists.
