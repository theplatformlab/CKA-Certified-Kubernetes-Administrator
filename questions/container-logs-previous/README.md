# Logs of a crashed container

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `diag`:

1. The container `worker` of pod `{{POD}}` crashed once and was restarted. Save the complete log output of the **crashed** instance of that container into `{{WORKDIR}}/previous.log`.
2. Before crashing, the container printed a session token. Write only the token into `{{WORKDIR}}/token.txt`.
3. Pod `gateway` runs two containers. Write all log lines of container `auth` that contain `ERROR`, and nothing else, into `{{WORKDIR}}/auth-errors.log`.

## Hints

- `kubectl logs` shows the current instance of a container. There is a flag for the instance before the last restart.
- `k -n diag logs {{POD}} -c worker --previous` (or `-p`). Look at `RESTARTS` in `k -n diag get pod` first.
- For a multi-container pod, `kubectl logs` picks the default container unless you pass `-c auth`; filter with `grep ERROR`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n diag get pod {{POD}}                       # RESTARTS 1
k -n diag logs {{POD}} -c worker                # the new instance: "restarted after crash ..."
k -n diag logs {{POD}} -c worker --previous > {{WORKDIR}}/previous.log
grep token {{WORKDIR}}/previous.log             # session token: {{TOKEN}}
echo {{TOKEN}} > {{WORKDIR}}/token.txt

k -n diag get pod gateway -o jsonpath='{.spec.containers[*].name}'     # proxy auth
k -n diag logs gateway -c auth | grep ERROR > {{WORKDIR}}/auth-errors.log
```

`--previous` reads the log file the kubelet keeps for the last terminated instance of the container. Without it you only see the instance that is running now, which here no longer prints the token. In pod `gateway`, `proxy` is marked as the default container (annotation `kubectl.kubernetes.io/default-container`), so `kubectl logs gateway` without `-c` shows the wrong container, which logs `ERROR` lines too.
