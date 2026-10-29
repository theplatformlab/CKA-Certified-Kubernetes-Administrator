# Pod Security Standards

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `restricted` runs Deployment `web`.

1. Configure Pod Security Admission on namespace `restricted`:
   - `enforce` at level `restricted`
   - `warn` at level `restricted`
   - `audit` at level `baseline`
2. Update Deployment `web` so that its pods are admitted under the `restricted` level, and make sure all its replicas are Running. Do not change the image.

Privileged pods must then be rejected in this namespace.

## Hints

- Pod Security Admission is configured with namespace labels `pod-security.kubernetes.io/<mode>=<level>`.
- Labelling doesn't touch running pods. Restart the Deployment and read the warnings and the ReplicaSet events.
- Restricted needs runAsNonRoot, seccompProfile RuntimeDefault, allowPrivilegeEscalation false and capabilities drop ALL.

## Solution

```bash
k config use-context {{CONTEXT}}
k label ns restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=baseline
k -n restricted rollout restart deploy web    # warning lists what's missing; new pods are rejected
k -n restricted edit deploy web
```

```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: nginx-unprivileged
        image: nginxinc/nginx-unprivileged:1.28-alpine
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

```bash
k -n restricted rollout status deploy web
k -n restricted run priv --image=busybox:1.37 \
  --overrides='{"spec":{"containers":[{"name":"priv","image":"busybox:1.37","securityContext":{"privileged":true}}]}}'
# Error ... violates PodSecurity "restricted:latest"
```

Labelling the namespace doesn't touch running pods. `enforce` only applies when pods are created. So check the ReplicaSet events (`k -n restricted describe rs`) after the restart.
