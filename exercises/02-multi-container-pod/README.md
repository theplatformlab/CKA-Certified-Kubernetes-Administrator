# Exercise 02 — Multi-Container Pod (Sidecar Logging)

> Related: [Pod skeleton](../../skeletons/pod.yaml) | [README — Workloads & Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Create a pod with a main container and a sidecar container that tails the main container's log file. This uses the v1.35 native sidecar container feature (`restartPolicy: Always` on an init container).

## Tasks

Work in namespace `exercise-02` (`./scripts/lab.sh setup 02` creates it).

1. Create a pod named `logger` in namespace `exercise-02` with:
   - An init container (sidecar) named `log-agent` using `busybox:1.37`
     - Set `restartPolicy: Always` on the init container to make it a native sidecar
     - Command: `tail -F /var/log/app/app.log` (capital F waits for file creation)
     - Mount the shared volume at `/var/log/app`
   - A main container named `app` using `busybox:1.37`
     - Command: append a line to `/var/log/app/app.log` every 3 seconds
     - Mount the same shared volume at `/var/log/app`
   - Use an `emptyDir` volume named `log-volume`
2. Verify both containers are running (READY `2/2`)
3. Check the sidecar's logs to see the streamed output

Validate with `./scripts/lab.sh check 02`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Native sidecars in v1.35: put the sidecar in `initContainers` with `restartPolicy: Always`
- The sidecar starts before the main container and keeps running alongside it
- Shared volume: both containers mount the same `emptyDir`

</details>

## What tripped me up

> First attempt: I put the sidecar in `containers` instead of `initContainers`. It ran, but it wasn't a native sidecar — it started alongside the main container with no ordering guarantee. The whole point of native sidecars (v1.35) is that they start *before* the main container and keep running. Has to be `initContainers` + `restartPolicy: Always`.
>
> Second mistake: the `tail -f` command failed silently because the log file didn't exist yet. The sidecar starts first (native sidecar starts before main container), before the app container writes anything. The log file is created by the app container, so the sidecar must use `tail -F` (capital F) which waits for the file to appear and follows it through rotations.

## Verify

```bash
./scripts/lab.sh check 02
```

Manual checks:

```bash
# Both containers should be Running (READY 2/2)
k get pod logger -n exercise-02

# Should see the log lines from the app container
k logs logger -n exercise-02 -c log-agent
```

## Cleanup

```bash
./scripts/lab.sh cleanup 02
```

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: logger
  namespace: exercise-02
spec:
  initContainers:
  - name: log-agent
    image: busybox:1.37
    restartPolicy: Always
    command: ["sh", "-c", "tail -F /var/log/app/app.log"]
    volumeMounts:
    - name: log-volume
      mountPath: /var/log/app
  containers:
  - name: app
    image: busybox:1.37
    command: ["sh", "-c", "while true; do echo \"$(date) - app running\" >> /var/log/app/app.log; sleep 3; done"]
    volumeMounts:
    - name: log-volume
      mountPath: /var/log/app
  volumes:
  - name: log-volume
    emptyDir: {}
```

```bash
k create ns exercise-02     # or: ./scripts/lab.sh setup 02
k apply -f logger.yaml

# Wait for pod to be ready
k get pod logger -n exercise-02 -w

# Check sidecar logs
k logs logger -n exercise-02 -c log-agent
```

</details>
