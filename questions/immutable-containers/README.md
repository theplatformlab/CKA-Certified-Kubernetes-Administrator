# Immutable containers

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `invoice-svc` only immutable containers may run. Here a container counts as **immutable** when it

- has a read-only root filesystem (`readOnlyRootFilesystem: true`),
- is not privileged, and
- does not run as root: the effective `runAsUser` (container level wins over pod level) is set and not `0`.

1. Find the standalone pods in `invoice-svc` that have at least one container that is not immutable and delete them. Pods whose containers are all immutable must keep running.
2. Make Deployment `invoice-web` immutable: its container must get a read-only root filesystem. nginx still needs to write temporary files to `/tmp`, so give it an `emptyDir` volume there. The Deployment must be fully rolled out and serving on port `8080` afterwards. (Its image already runs as non-root UID 101.)

## Hints

- `k -n invoice-svc get pods -o yaml` shows both the pod-level and the container-level `securityContext`. Check every container of a pod, and remember that a container's `runAsUser` overrides the pod's.
- A jsonpath like `{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\t"}{.spec.containers[*].securityContext}{"\n"}{end}` puts everything on one line per pod.
- With only `readOnlyRootFilesystem: true`, nginx fails to start (`mkdir() "/tmp/client_temp" failed (30: Read-only file system)`). Check `k logs` of the new pods.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n invoice-svc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext}{"\t"}{.spec.containers[*].securityContext}{"\n"}{end}'
# pdf-renderer   {"runAsNonRoot":true,"runAsUser":1000}  {"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true}  -> immutable
# mailer         {"runAsUser":1000}   {"privileged":true,"readOnlyRootFilesystem":true}                                -> privileged
# ledger-sync    {}                   {}                                                                               -> writable, root
# tax-calc       {"runAsUser":0}      {"readOnlyRootFilesystem":true,"runAsUser":2000}                                 -> immutable (container wins)
# audit-shipper  {"runAsUser":1000}   {"readOnlyRootFilesystem":true} {"readOnlyRootFilesystem":false}                 -> sidecar writable
# fx-rates       {}                   {"readOnlyRootFilesystem":true,"runAsUser":0}                                    -> root
k -n invoice-svc delete pod mailer ledger-sync audit-shipper fx-rates

k -n invoice-svc edit deployment invoice-web
```

```yaml
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:1.28-alpine
        ports:
        - containerPort: 8080
        securityContext:
          readOnlyRootFilesystem: true
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
```

```bash
k -n invoice-svc rollout status deployment invoice-web
k -n invoice-svc exec deploy/invoice-web -- touch /etc/test     # Read-only file system
k -n invoice-svc exec deploy/invoice-web -- touch /tmp/test     # works
```

Immutability means the container's filesystem can't be changed at runtime: an attacker can't drop binaries or alter config, and every restart starts from the image again. The pod-level `securityContext` is only a default for the containers; `tax-calc` sets `runAsUser: 0` there but its only container overrides it with `2000`, so it stays. `audit-shipper` is the opposite case: its main container is fine, but the `log-agent` sidecar has a writable root filesystem, which makes the pod mutable. Pods can't have their `securityContext` changed in place, so a standalone pod is fixed by deleting (and, if needed, recreating) it. Writable paths an app really needs are mounted as `emptyDir` volumes, which keeps the rest of the filesystem read-only.
