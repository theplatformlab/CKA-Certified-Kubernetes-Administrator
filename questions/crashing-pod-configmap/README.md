# Fix a crashing pod with a ConfigMap

**Context:** `kubectl config use-context {{CONTEXT}}`

Pod `app-frontend` in namespace `production` is in `CrashLoopBackOff`. It expects a configuration file at `/etc/app/config.yaml`, but the file does not exist. The pod's manifest is saved at `{{WORKDIR}}/app-frontend.yaml`.

1. Create a ConfigMap named `app-config` in namespace `production` with one key, `config.yaml`, whose content is exactly:
   `database_host: postgres.production.svc.cluster.local`
2. Make the ConfigMap available to pod `app-frontend` so that the file `/etc/app/config.yaml` contains that content.
3. The pod must keep its name, image and command, and must be `Running`.

## Hints

- Look at the pod's logs first: what exactly is missing?
- `kubectl create configmap ... --from-literal=<key>=<value>`: the key becomes the file name when mounted.
- Volumes of a running pod can't be changed. Edit the saved manifest and use `kubectl replace --force -f`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n production logs app-frontend          # FATAL: /etc/app/config.yaml not found

k -n production create configmap app-config \
  --from-literal=config.yaml='database_host: postgres.production.svc.cluster.local'
```

Pod volumes are immutable, so edit the saved manifest and replace the pod:

```yaml
# {{WORKDIR}}/app-frontend.yaml (added parts)
spec:
  containers:
  - name: app
    # ... image and command unchanged ...
    volumeMounts:
    - name: config
      mountPath: /etc/app
  volumes:
  - name: config
    configMap:
      name: app-config
```

```bash
k replace --force -f {{WORKDIR}}/app-frontend.yaml
k -n production exec app-frontend -- cat /etc/app/config.yaml
```

Mounting the whole ConfigMap at `/etc/app` is fine, because the key name becomes the file name. If `/etc/app` held other files, you would use `mountPath: /etc/app/config.yaml` with `subPath: config.yaml` instead.
