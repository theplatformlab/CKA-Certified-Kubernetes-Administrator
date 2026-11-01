# Kustomize cleanup and an HPA per environment

**Context:** `kubectl config use-context {{CONTEXT}}`

The bookstore application is deployed with Kustomize from `{{WORKDIR}}/bookstore`: a `base` and the overlays `overlays/staging` (namespace `bookstore-staging`) and `overlays/prod` (namespace `bookstore-prod`). Both overlays are applied.

1. The summer promotion is over. Remove the ConfigMap `promo-config` from the configuration entirely, together with everything that refers to it. Each overlay must still build with `kubectl kustomize`.
2. Add a HorizontalPodAutoscaler (`autoscaling/v2`) named `bookstore` to the base. It targets Deployment `bookstore`, scales between `{{HPA_MIN}}` and `{{HPA_MAX}}` replicas and keeps the average CPU utilization at `{{CPU}}%`.
3. In prod the HPA may scale up to `{{PROD_MAX}}` replicas. Change this in the prod overlay only.
4. Apply both overlays. Afterwards, ConfigMap `promo-config` must not exist in either namespace, and the bookstore pods must be running.

## Hints

- `k kustomize <dir>` renders a kustomization without applying it. Run it for the base and both overlays after every change.
- Look for `promo-config` in every file under `{{WORKDIR}}/bookstore` (`grep -r`): a resource list, the Deployment and a patch in each overlay refer to it. A strategic merge patch whose object is gone breaks the build; a patch with a `target` selector is skipped silently, but it is still a reference.
- `k apply -k` creates and updates objects, it never deletes the ones you removed from the files. Delete the old ConfigMap in both namespaces yourself.

## Solution

```bash
k config use-context {{CONTEXT}}
cd {{WORKDIR}}/bookstore
grep -rn promo-config .
```

Remove the ConfigMap and every reference to it:

- `base/kustomization.yaml`: drop `promo-config.yaml` from `resources` and delete the file
- `base/deployment.yaml`: drop the `envFrom` block
- `overlays/staging`: drop the `patches` entry and delete `promo-patch.yaml`
- `overlays/prod/kustomization.yaml`: drop the patch that targets `kind: ConfigMap`

Create `base/hpa.yaml` and add it to `resources` in `base/kustomization.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: bookstore
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: bookstore
  minReplicas: {{HPA_MIN}}
  maxReplicas: {{HPA_MAX}}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{CPU}}
```

Add a patch to `overlays/prod/kustomization.yaml`:

```yaml
patches:
- path: replicas-patch.yaml
- target:
    kind: HorizontalPodAutoscaler
    name: bookstore
  patch: |-
    - op: replace
      path: /spec/maxReplicas
      value: {{PROD_MAX}}
```

```bash
k kustomize base
k kustomize overlays/staging
k kustomize overlays/prod                  # no ConfigMap, HPA maxReplicas {{PROD_MAX}}

k apply -k overlays/staging
k apply -k overlays/prod
k -n bookstore-staging delete configmap promo-config
k -n bookstore-prod delete configmap promo-config
k get hpa,cm,deploy -n bookstore-staging
k get hpa,cm,deploy -n bookstore-prod
```

`k apply -k` only knows the objects in the current build, so the ConfigMap stays in the cluster until you delete it (`k apply -k ... --prune -l <selector>` would also remove it, but pruning is deprecated and easy to get wrong). Remove the `envFrom` reference before or together with the ConfigMap: a pod that refers to a missing ConfigMap fails with `CreateContainerConfigError` when it is recreated. A strategic merge patch for an object that is no longer in the build makes `kubectl kustomize` fail, so the staging patch has to go too. The prod patch selects its object with `target`, which matches nothing now and is skipped without an error; it is dead configuration, so it goes as well.
