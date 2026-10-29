# Exercise 14 — Kustomize: Base and Overlay

> **Medium** | ~15 min | Domain: Cluster Architecture (25%)
>
> Related: [README — Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25)

Build a base deployment and apply an overlay that changes the namespace and replica count. Kustomize is built into kubectl and is now part of the CKA skill set.

## Tasks

Work in namespace `exercise-14` (`./scripts/lab.sh setup 14` creates it). Write the files under `~/cka-lab/ex14/` — the check renders them from that exact path.

1. Create a directory structure in `~/cka-lab/ex14/`:
   ```
   kustomize-lab/
     base/
       deployment.yaml
       service.yaml
       kustomization.yaml
     overlays/
       staging/
         kustomization.yaml
   ```
2. In the base (no namespace, no environment label):
   - A Deployment named `app` with pod label `app=app`, one container `nginx` with image `nginx:1.27`, and 1 replica
   - A ClusterIP Service named `app-svc` on port 80, selecting `app=app`
   - A `kustomization.yaml` listing both resources
3. In the staging overlay:
   - Set namespace to `exercise-14`
   - Patch replicas to 3 (in the overlay — the base keeps 1)
   - Add a common label `env: staging` (on the objects, the pod template and the selectors)
4. Apply the staging overlay with `kubectl apply -k`
5. Verify 3 pods are running in namespace `exercise-14` with label `env=staging`

Validate with `./scripts/lab.sh check 14`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `kubectl apply -k <overlay-dir>/`
- `kubectl kustomize <overlay-dir>/` to preview the output without applying
- Overlay `kustomization.yaml` references the base with `resources: [../../base]`
- Use `replicas` field in kustomization.yaml to patch replica count
- `commonLabels` still works but is deprecated in Kustomize v5; the replacement is `labels:` with `includeSelectors: true`

</details>

## What tripped me up

> All paths in `kustomization.yaml` are relative to the file's location. I used an absolute path (`/home/user/kustomize-lab/base/`) and got a cryptic error about paths not being within the root. Keep everything relative: `../../base` from the overlay directory. This bit me twice during practice.
>
> Also: I forgot the `resources:` field in the overlay kustomization.yaml. Without pointing to the base, Kustomize has nothing to patch. It just silently produces empty output. I applied it and wondered why nothing was created. Run `kubectl kustomize <dir>/ | less` first to preview what you're about to apply — if it's empty, something's wrong with your kustomization.yaml.

## Verify

```bash
./scripts/lab.sh check 14
```

Manual checks:

```bash
# Preview: base has 1 replica, overlay has 3 in exercise-14
k kustomize ~/cka-lab/ex14/kustomize-lab/base/
k kustomize ~/cka-lab/ex14/kustomize-lab/overlays/staging/

# 3 pods running
k get pods -n exercise-14 -l env=staging

# Label applied
k get deploy app -n exercise-14 --show-labels | grep staging

# Service created
k get svc app-svc -n exercise-14
```

## Cleanup

```bash
./scripts/lab.sh cleanup 14
rm -rf ~/cka-lab/ex14/
```

<details>
<summary>Solution</summary>

```bash
cd ~/cka-lab/ex14
mkdir -p kustomize-lab/base kustomize-lab/overlays/staging
```

base/deployment.yaml:
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
        image: nginx:1.27
        ports:
        - containerPort: 80
```

base/service.yaml:
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

base/kustomization.yaml:
```yaml
resources:
- deployment.yaml
- service.yaml
```

overlays/staging/kustomization.yaml:
```yaml
resources:
- ../../base

namespace: exercise-14

labels:
- pairs:
    env: staging
  includeSelectors: true   # same effect as the older commonLabels

replicas:
- name: app
  count: 3
```

```bash
k kustomize kustomize-lab/overlays/staging/   # preview
k apply -k kustomize-lab/overlays/staging/

# Verify
k get pods -n exercise-14
k get deploy app -n exercise-14 --show-labels
k get svc app-svc -n exercise-14
```

</details>
