# Harden a Deployment with security contexts

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `invoice-api` in namespace `hardened-apps` runs as root with the container runtime's default capabilities. Harden it:

1. In the **pod's** security context: run as user `{{RUN_UID}}` and group `{{RUN_GID}}`, refuse to start as root (`runAsNonRoot`), and give mounted volumes the group `{{FS_GID}}` (`fsGroup`).
2. In the **container's** security context: forbid privilege escalation, make the root filesystem read-only, drop all capabilities and add back only `{{CAP}}`.
3. The application writes to `/tmp`. Give it a writable `emptyDir` volume mounted at `/tmp`.

Do not change the image or the command. Both replicas must be Running and Ready, and the application must still answer on port 8080.

## Hints

- `k explain deploy.spec.template.spec.securityContext` (pod level: `runAsUser`, `runAsGroup`, `runAsNonRoot`, `fsGroup`) vs. `...containers.securityContext` (container level: `allowPrivilegeEscalation`, `readOnlyRootFilesystem`, `capabilities`).
- Capabilities are written without the `CAP_` prefix: `drop: ["ALL"]`, `add: ["{{CAP}}"]`.
- Pods crash after the change? `k -n hardened-apps logs <pod>`: a read-only root filesystem needs a volume wherever the app writes.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n hardened-apps edit deploy invoice-api
```

```yaml
    spec:
      securityContext:
        runAsUser: {{RUN_UID}}
        runAsGroup: {{RUN_GID}}
        runAsNonRoot: true
        fsGroup: {{FS_GID}}
      containers:
      - name: api
        image: busybox:1.37
        command: [...]                    # unchanged
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
            add: ["{{CAP}}"]
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
```

```bash
k -n hardened-apps rollout status deploy invoice-api
k -n hardened-apps exec deploy/invoice-api -- id          # uid={{RUN_UID}} gid={{RUN_GID}} groups={{FS_GID}}
k -n hardened-apps exec deploy/invoice-api -- ls -ld /tmp  # group {{FS_GID}}, setgid bit
k -n hardened-apps exec deploy/invoice-api -- touch /x     # Read-only file system
k -n hardened-apps exec deploy/invoice-api -- grep Cap /proc/1/status
```

Without the `/tmp` volume the pods crash with `mkdir: can't create directory '/tmp/www': Read-only file system`. `fsGroup` adds the group to the process and makes it the group owner of the emptyDir; `runAsGroup` only sets the primary group. Most of these fields exist on one level only: `fsGroup` only on the pod, `capabilities`, `readOnlyRootFilesystem` and `allowPrivilegeEscalation` only on the container (`runAsUser`, `runAsGroup` and `runAsNonRoot` exist on both, the container value wins). A non-root process gets the added capability only in its bounding set (`CapBnd`), not in its effective set, unless the binary has file capabilities.
