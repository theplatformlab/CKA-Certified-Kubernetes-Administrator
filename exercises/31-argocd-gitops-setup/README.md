# Exercise 31 — Argo CD Setup (GitOps Deployment)

> Supplemental product practice: Argo CD is not named in the current CKA curriculum. The exercise can still help practice CRDs and Kubernetes manifests; see the [official curriculum](https://github.com/cncf/curriculum/blob/master/CKA_Curriculum_v1.37.pdf) for exam scope.
>
> Related: [README — Deployments](../../README.md#domain-3--workloads--scheduling-15)

Install Argo CD from a Helm chart template and configure it to deploy applications from a Git repository. Tests Helm templating, CRD handling and GitOps concepts.

## Tasks

This exercise requires `helm` on your workstation and runs on the practice cluster (`./scripts/lab.sh setup 31` prepares it). The Argo CD v3.5.6 CRDs are already installed (`applications`, `applicationsets`, `appprojects` in `argoproj.io`), like an exam environment where "the CRDs are already installed". The Application deploys into namespace `exercise-31`; Argo CD creates it.

1. Add the official Argo CD Helm repository under the name `argo`: `https://argoproj.github.io/argo-helm`
2. Generate a template of chart `argo/argo-cd` version **10.11.6** (Argo CD v3.5.6) with release name `argocd` for namespace `argocd`:
   - Configure the chart to NOT install CRDs — they already exist
   - Save the output to `~/argo-helm.yaml`
3. Create namespace `argocd` and apply `~/argo-helm.yaml` to it
4. Verify all Argo CD components are Running (`argocd-server`, `argocd-repo-server`, `argocd-application-controller`, ...)
5. Create an Application `guestbook` in namespace `argocd`:
   - project `default`
   - source: repo `https://github.com/argoproj/argocd-example-apps.git`, revision `HEAD`, path `guestbook`
   - destination: `https://kubernetes.default.svc`, namespace `exercise-31`
   - automated sync with `prune` and `selfHeal`, sync option `CreateNamespace=true`
6. Verify the application is `Synced` and `Healthy` and that Deployment and Service `guestbook-ui` exist in `exercise-31`
7. Create a port-forward to Argo CD UI (optional testing)

Validate with `./scripts/lab.sh check 31`.

## Key Learning

- GitOps: cluster state matches Git repository
- Argo CD Application resource is a CRD
- The argo-cd chart renders its CRDs as normal templates — `helm template` includes them unless `crds.install=false`
- Applying the Application before the CRD exists fails with `no matches for kind "Application"`
- Application must specify repoURL, path, destination
- Exam tests CRD understanding and GitOps workflow

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `helm repo add argo https://argoproj.github.io/argo-helm && helm repo update`
- Chart versions: `helm search repo argo/argo-cd --versions | head` (CHART VERSION ≠ APP VERSION)
- Find the CRD switch: `helm show values argo/argo-cd --version 10.11.6 | grep -A3 '^crds:'`
- `helm template` only prints; nothing is installed until you `k apply` the file
- Wait for server to start: `k get pod -n argocd -l app.kubernetes.io/name=argocd-server`
- Application spec needs: `repoURL`, `path`, `destination.namespace`
- Sync status: `k get application -A`

</details>

## What tripped me up

> I installed Argo CD with CRDs included and then the Application CRD already existed. Then when I tried to apply the Application manifest, it didn't have the right fields. Argo CD has a specific Application spec structure that's different from regular Deployments. The exam said "generate WITHOUT CRDs" — follow instructions exactly. Also: the Git repository URL matters — wrong URL means Application stays out-of-sync. Test the repo URL is accessible BEFORE applying the Application.

## Verify

```bash
./scripts/lab.sh check 31
```

Manual checks:

```bash
# The template has no CRDs
grep -c '^kind: CustomResourceDefinition' ~/argo-helm.yaml     # 0

# Argo CD is running
k get pod -n argocd

# Argo CD server is accessible
k port-forward -n argocd svc/argocd-server 8080:443

# Application resource exists and is in sync
k get application -A

# Get application sync and health status
k get application -n argocd guestbook -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
# Should show: Synced Healthy

# Check deployed resources
k get deployment,service -n exercise-31
```

## Cleanup

```bash
./scripts/lab.sh cleanup 31
```

This deletes the Application, namespaces `exercise-31` and `argocd`, the Argo CD ClusterRoles/Bindings and CRDs, and `~/argo-helm.yaml`.

<details>
<summary>Solution</summary>

```bash
# 1. Add the Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head -3

# 2. Render the chart without CRDs (they are pre-installed)
helm show values argo/argo-cd --version 10.11.6 | grep -A3 '^crds:'
helm template argocd argo/argo-cd --version 10.11.6 \
  --namespace argocd \
  --set crds.install=false \
  > ~/argo-helm.yaml
grep -c '^kind: CustomResourceDefinition' ~/argo-helm.yaml   # 0

# 3. Create the namespace and apply the template
k create namespace argocd
k apply -n argocd -f ~/argo-helm.yaml

# 4. Wait for Argo CD to be ready
k -n argocd wait --for=condition=available --timeout=300s deployment --all
k -n argocd rollout status statefulset argocd-application-controller --timeout=300s
k get pod -n argocd

# 5. Create an Application manifest (GitOps)
cat <<EOF > application.yaml
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
    namespace: exercise-31
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# 6. Apply the Application
k apply -f application.yaml

# 7. Watch sync status (Synced / Healthy after ~1 minute)
k get application -n argocd -w

# 8. Verify resources created by Argo CD
k get deployment,service -n exercise-31

# 9. Access Argo CD UI (optional)
k port-forward -n argocd svc/argocd-server 8080:443
# Navigate to https://localhost:8080
# Default password: admin / (stored in secret)
# Get password: k get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d

# 10. View application sync status
k get application guestbook -n argocd -o jsonpath='{.status.sync.status}'
# Output: Synced
```

References:
- Argo CD Docs: https://argo-cd.readthedocs.io/
- Argo CD Helm chart: https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
- Application CRD: https://argo-cd.readthedocs.io/en/stable/declarative-setup/

</details>
