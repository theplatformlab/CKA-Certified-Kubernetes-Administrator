# Pod Security Admission

**Context:** `kubectl config use-context {{CONTEXT}}`

1. Create namespace `secure-apps` with Pod Security Admission `enforce` and `warn` both set to level `restricted`.
2. Create a pod `restricted-pod` in `secure-apps` with image `nginxinc/nginx-unprivileged:1.28-alpine` that complies with the `restricted` level and is Running.
3. Try to create a pod `blocked-pod` in `secure-apps` with image `busybox:1.37`, command `sleep 3600` and `securityContext.privileged: true`. Save the error message to `{{WORKDIR}}/error.txt`.

## Hints

- Pod Security Admission is configured with namespace labels `pod-security.kubernetes.io/enforce|warn|audit=<level>`.
- A restricted pod needs runAsNonRoot, seccompProfile RuntimeDefault, allowPrivilegeEscalation false and capabilities drop ALL.
- The rejection is printed on stderr: redirect with `2>`.

## Solution

```bash
k config use-context {{CONTEXT}}
k create ns secure-apps
k label ns secure-apps pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
  namespace: secure-apps
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: web
    image: nginxinc/nginx-unprivileged:1.28-alpine
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

```bash
k apply -f restricted-pod.yaml
k -n secure-apps run blocked-pod --image=busybox:1.37 \
  --overrides='{"spec":{"containers":[{"name":"blocked-pod","image":"busybox:1.37","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}' \
  2> {{WORKDIR}}/error.txt
cat {{WORKDIR}}/error.txt
# Error from server (Forbidden): pods "blocked-pod" is forbidden: violates PodSecurity "restricted:latest": privileged ...
```

The error goes to stderr, so use `2>`. With `>` you capture nothing.
