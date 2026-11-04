# Kustomize base and overlay

**Context:** `kubectl config use-context {{CONTEXT}}`

Package an app with Kustomize under `{{WORKDIR}}/kustomize-lab`, with a `base` and an overlay `overlays/staging`:

1. The base (no namespace, no environment label) contains:
   - a Deployment `app` with 1 replica, pod label `app=app` and one container `nginx` with image `nginx:1.28`
   - a ClusterIP Service `app-svc` on port `80` that selects `app=app`
2. The overlay `overlays/staging` uses the base and:
   - puts everything into namespace `staging-apps`
   - runs `{{REPLICAS}}` replicas (the base keeps 1)
   - adds the label `env=staging` to all objects, the pod template and the selectors
3. Apply the staging overlay. All {{REPLICAS}} pods must be Running in namespace `staging-apps`, and the Service must have {{REPLICAS}} endpoints.

## Hints

- `kubectl kustomize <dir>` renders a kustomization without applying it, `kubectl apply -k <dir>` applies it.
- The overlay's `kustomization.yaml` points to the base with `resources: [../../base]`; paths are relative to the file.
- `replicas:` in a kustomization changes the replica count without a patch. `labels:` with `includeSelectors: true` replaces the deprecated `commonLabels`.

## Solution

```bash
cd {{WORKDIR}}
mkdir -p kustomize-lab/base kustomize-lab/overlays/staging
cd kustomize-lab
k create deployment app --image=nginx:1.28 --dry-run=client -o yaml > base/deployment.yaml
```

`base/deployment.yaml` (generated, cleaned up; the container is named `nginx`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
```

`base/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-svc
spec:
  selector:
    app: app
  ports:
  - port: 80
    targetPort: 80
```

`base/kustomization.yaml`:

```yaml
resources:
- deployment.yaml
- service.yaml
```

`overlays/staging/kustomization.yaml`:

```yaml
resources:
- ../../base
namespace: staging-apps
labels:
- pairs:
    env: staging
  includeSelectors: true
replicas:
- name: app
  count: {{REPLICAS}}
```

```bash
k kustomize overlays/staging          # preview
k apply -k overlays/staging
k -n staging-apps get pods -l env=staging
```

## Pitfalls

- An overlay without `resources: [../../base]` renders nothing, and applying it silently creates nothing. Preview with `kubectl kustomize` first.
- Absolute paths in `resources` fail with an error about files outside the kustomization root. Keep them relative.
