# Harden a Dockerfile and its pod manifest

**Context:** `kubectl config use-context {{CONTEXT}}`

A team wants to ship its report generator. Review the files in `{{WORKDIR}}`: `Dockerfile`, `app.py` (a plain Python script without dependencies) and `pod.yaml`. Fix them in place; do not build the image or create the pod.

`Dockerfile`:

1. Use the small, pinned base image `python:3.13-alpine` instead of `ubuntu:latest`.
2. Do not install any packages: the app needs nothing but Python.
3. The API token must not be part of the image (it will come from a Secret at runtime).
4. The container must run as the non-root user with UID `10001`.
5. Keep copying `app.py` to `/app/app.py` and starting it with `python3 /app/app.py`.

`pod.yaml` (pod `report-gen` in namespace `report-gen`, which enforces the `restricted` Pod Security Standard):

6. Take `API_TOKEN` from key `token` of the existing Secret `report-api`; the token value must not appear in the file.
7. The container must not be privileged, must run as non-root with UID `10001`, have a read-only root filesystem, and the pod must be admitted in namespace `report-gen` (check with `k apply --dry-run=server -f pod.yaml`).

## Hints

- Every `RUN`, `COPY` and `ENV` creates a layer that anyone who pulls the image can read (`docker history`, `docker save`). A secret in an `ENV` or `ARG` stays in the image even if a later instruction removes it.
- `USER 10001` works without a passwd entry. Instructions after the last `USER` and the container process run as that user.
- The `restricted` profile requires `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` and `seccompProfile.type: RuntimeDefault`. `privileged: true` is never allowed. If `kubesec` is installed, `kubesec scan pod.yaml` scores the manifest.

## Solution

```bash
k config use-context {{CONTEXT}}
cd {{WORKDIR}}
cat > Dockerfile <<'EOF'
FROM python:3.13-alpine
COPY app.py /app/app.py
USER 10001
CMD ["python3", "/app/app.py"]
EOF
```

```yaml
# {{WORKDIR}}/pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: report-gen
  namespace: report-gen
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: registry.example.com/report-gen:1.4.0
    env:
    - name: API_TOKEN
      valueFrom:
        secretKeyRef:
          name: report-api
          key: token
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

```bash
k apply --dry-run=server -f pod.yaml        # pod/report-gen created (server dry run)
```

`ubuntu:latest` plus `apt-get install` brought a shell toolbox (curl, wget, netcat, vim) that an attacker in the container would love, and `latest` changes under you with every pull. The alpine-based Python image already contains the interpreter, so the `RUN` line can go entirely, and with it the package cache layers. For an even smaller attack surface, a distroless or multi-stage build is the next step, and pinning by digest (`python:3.13-alpine@sha256:...`) makes the build reproducible. The token belonged to neither file: an `ENV` line in the Dockerfile ends up in the image config, and a `value:` in the manifest ends up in Git; `secretKeyRef` resolves it from the Secret when the pod starts.
