# ConfigMap changes and running pods

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `config-app` in namespace `config-demo` uses ConfigMap `app-config`. It reads key `mode` as environment variable `APP_MODE`, and the ConfigMap is also mounted at `/etc/app`.

1. Change the ConfigMap: set `mode` to `production` and `message` to `v2`.
2. Make sure all pods of `config-app` use the new values, both in the environment variable and in the file `/etc/app/message`. Do not delete the Deployment.

## Hints

- Environment variables are read once, when the container starts.
- Mounted ConfigMap files are updated in place after a while, environment variables never.
- `kubectl rollout restart deployment/<name>` replaces the pods without deleting the Deployment.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n config-demo patch cm app-config -p '{"data":{"mode":"production","message":"v2"}}'
k -n config-demo rollout restart deploy config-app
k -n config-demo rollout status deploy config-app
k -n config-demo exec deploy/config-app -- sh -c 'echo $APP_MODE; cat /etc/app/message'
```

Mounted ConfigMap files are updated in place by the kubelet after up to about a minute (not with `subPath`). Environment variables are only read when the container starts. So the env var needs new pods, and `rollout restart` gives you that without deleting the Deployment.
