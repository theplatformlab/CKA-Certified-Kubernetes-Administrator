# Resize a running pod in place

**Context:** `kubectl config use-context {{CONTEXT}}`

Pod `trainer` in namespace `ml-training` (not managed by any controller) needs more resources, but it must not lose its state: it may neither be deleted and recreated nor have its container restarted.

Resize its container `trainer` to:

| | request | limit |
|---|---|---|
| CPU | `{{CPU_REQ}}` | `{{CPU_LIM}}` |
| memory | `{{MEM_REQ}}` | `{{MEM_LIM}}` |

The new values must be in effect on the running container.

## Hints

- `k edit pod` or a normal `k patch pod` is refused: container resources are changed through the pod's `resize` subresource.
- `k patch pod <name> --subresource resize --patch '...'` (or `k edit pod <name> --subresource resize`).
- `k describe pod` shows the container's `resizePolicy`; `.status.containerStatuses[0].resources` shows what the kubelet has applied, conditions `PodResizePending` / `PodResizeInProgress` show a resize that isn't done.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n ml-training get pod trainer -o jsonpath='{.spec.containers[0].resizePolicy}'   # cpu, memory: NotRequired
k -n ml-training patch pod trainer --subresource resize --patch \
  '{"spec":{"containers":[{"name":"trainer","resources":{"requests":{"cpu":"{{CPU_REQ}}","memory":"{{MEM_REQ}}"},"limits":{"cpu":"{{CPU_LIM}}","memory":"{{MEM_LIM}}"}}}]}}'

k -n ml-training get pod trainer -o jsonpath='{.status.containerStatuses[0].resources}{"\n"}'
k -n ml-training get pod trainer                    # RESTARTS 0, same AGE
```

In-place resize is GA since v1.35. Without `--subresource resize` the API server answers `pod updates may not change fields other than ...`. The QoS class can't change by a resize (this pod stays Burstable). With `restartPolicy: RestartContainer` for memory in `resizePolicy`, the same patch would restart the container. A node without enough free capacity leaves the resize `PodResizePending` (reason `Infeasible` or `Deferred`).
