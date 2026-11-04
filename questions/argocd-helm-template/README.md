# Install Argo CD from a Helm template

**Context:** `kubectl config use-context {{CONTEXT}}`

Install Argo CD and let it deploy a first application. The Argo CD CustomResourceDefinitions (`applications`, `applicationsets`, `appprojects` in API group `argoproj.io`) are already installed in the cluster.

1. Add the Helm repository `https://argoproj.github.io/argo-helm` under the name `argo`.
2. Render chart `argo/argo-cd` version `10.11.6` with release name `argocd` for namespace `argocd` into the file `{{WORKDIR}}/argo-helm.yaml`. The chart must not render the CRDs, they already exist.
3. Create namespace `argocd` and apply the rendered manifests to it. All Argo CD components must become ready.
4. Create an Argo CD Application named `guestbook` in namespace `argocd`:
   - project `default`
   - source: repository `https://github.com/argoproj/argocd-example-apps.git`, revision `HEAD`, path `guestbook`
   - destination: the in-cluster API server `https://kubernetes.default.svc`, namespace `guestbook`
   - automated sync with `prune` and `selfHeal`, and the sync option `CreateNamespace=true`

The Application must be `Synced` and `Healthy`.

## Hints

- `helm search repo argo/argo-cd --versions` lists chart versions (the CHART VERSION, not the APP VERSION).
- `helm show values argo/argo-cd --version 10.11.6 | grep -A3 '^crds:'` shows the switch for the CRDs.
- `helm template` only prints manifests; nothing is installed until you apply the file.
- `kubectl explain application.spec --recursive` works once the CRDs are installed.

## Solution

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm template argocd argo/argo-cd --version 10.11.6 --namespace argocd \
  --set crds.install=false > {{WORKDIR}}/argo-helm.yaml
grep -c '^kind: CustomResourceDefinition' {{WORKDIR}}/argo-helm.yaml   # 0

k create namespace argocd
k apply -n argocd -f {{WORKDIR}}/argo-helm.yaml
k -n argocd wait --for=condition=Available deployment --all --timeout=300s
k -n argocd rollout status statefulset argocd-application-controller
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

```bash
k apply -f application.yaml
k -n argocd get application guestbook -w     # Synced / Healthy after about a minute
k -n guestbook get deploy,svc
```

## Pitfalls

- The argo-cd chart renders its CRDs as ordinary templates, so `helm template` includes them unless `crds.install=false`. `--skip-crds` only affects charts that keep CRDs in a `crds/` directory.
- `helm template` without `--namespace argocd` renders objects for namespace `default`, and the ClusterRoleBindings then point to ServiceAccounts in the wrong namespace.
