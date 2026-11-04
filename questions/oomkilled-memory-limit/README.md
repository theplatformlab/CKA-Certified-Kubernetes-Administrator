# Container keeps restarting

**Context:** `kubectl config use-context {{CONTEXT}}`

The pod of Deployment `cache-warmer` in namespace `cache` keeps restarting and never stays ready.

Find the cause and fix it:

1. Set the memory limit of container `warmer` to `{{MEM_LIMIT}}` and its memory request to `{{MEM_REQ}}`.
2. Keep the image, the command and the CPU request.
3. The new pod must be running without restarts.

## Hints

- `k -n cache get pods` and `k -n cache describe pod -l app=cache-warmer`: look at `Last State` and its `Reason`.
- `OOMKilled` with exit code 137: the kernel killed the process because the container used more memory than its limit.
- `k set resources deploy/cache-warmer -c warmer --limits=memory=... --requests=memory=...`

## Solution

```bash
k config use-context {{CONTEXT}}
k -n cache get pods                                   # RESTARTS growing, CrashLoopBackOff
k -n cache describe pod -l app=cache-warmer | grep -A4 'Last State'
#   Last State:  Terminated
#     Reason:    OOMKilled
#     Exit Code: 137
k -n cache logs -l app=cache-warmer --previous        # "loading cache", never "cache loaded"

k -n cache set resources deploy/cache-warmer -c warmer \
  --limits=memory={{MEM_LIMIT}} --requests=memory={{MEM_REQ}}
k -n cache rollout status deploy/cache-warmer
k -n cache logs deploy/cache-warmer                   # cache loaded
```

`OOMKilled` is not an application error: the container's cgroup reached `limits.memory` and the kernel's OOM killer stopped the process. The only fixes are a higher limit or less memory use. `set resources` with only memory values leaves the CPU request untouched. The pod template changes, so the Deployment rolls out a new pod, and its restart counter starts at 0.
