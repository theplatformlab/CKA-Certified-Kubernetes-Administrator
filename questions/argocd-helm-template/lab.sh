# shellcheck shell=bash
# Install Argo CD from a Helm template. Sourced by scripts/lab.sh.
# Setup pre-installs the Argo CD CRDs ("the CRDs are already installed"); the
# candidate renders the chart without CRDs, applies it and creates an Application.
LAB_CLUSTER=practice
APP_NS=guestbook
ARGOCD_VERSION=v3.5.6       # appVersion of chart argo-cd 10.11.6
CHART_VERSION=10.11.6
TEMPLATE_FILE="$WORKDIR/argo-helm.yaml"
CRD_BASE="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/crds"

lab_setup() {
  local crd
  for crd in application appproject applicationset; do
    kc apply --server-side --force-conflicts -f "$CRD_BASE/${crd}-crd.yaml" >/dev/null
  done
  rm -f "$TEMPLATE_FILE"
  echo "  Argo CD $ARGOCD_VERSION CRDs installed."
}

lab_check() {
  check_gate "Template file argo-helm.yaml exists" test -s "$TEMPLATE_FILE"
  check "argo-helm.yaml was rendered from chart argo-cd $CHART_VERSION" \
    grep -q "helm.sh/chart: argo-cd-$CHART_VERSION" "$TEMPLATE_FILE"
  check_not "argo-helm.yaml contains no CustomResourceDefinition" \
    grep -q "^kind: CustomResourceDefinition" "$TEMPLATE_FILE"

  local d
  for d in argocd-server argocd-repo-server argocd-redis argocd-applicationset-controller; do
    check_eq "Deployment $d in argocd is available" \
      "$(jp -n argocd deploy "$d" '{.status.conditions[?(@.type=="Available")].status}')" "True"
  done
  check_eq "StatefulSet argocd-application-controller has 1 ready replica" \
    "$(jp -n argocd sts argocd-application-controller '{.status.readyReplicas}')" "1"

  local app="applications.argoproj.io"
  check_eq "Application guestbook: project default, repo argocd-example-apps, revision HEAD, path guestbook" \
    "$(jp -n argocd $app guestbook '{.spec.project} {.spec.source.repoURL} {.spec.source.targetRevision} {.spec.source.path}')" \
    "default https://github.com/argoproj/argocd-example-apps.git HEAD guestbook"
  check_eq "Application guestbook deploys to https://kubernetes.default.svc, namespace $APP_NS" \
    "$(jp -n argocd $app guestbook '{.spec.destination.server} {.spec.destination.namespace}')" \
    "https://kubernetes.default.svc $APP_NS"
  check_eq "Application guestbook syncs automatically (prune, selfHeal, CreateNamespace=true)" \
    "$(jp -n argocd $app guestbook '{.spec.syncPolicy.automated.prune} {.spec.syncPolicy.automated.selfHeal} {.spec.syncPolicy.syncOptions[*]}')" \
    "true true CreateNamespace=true"
  check_eq "Application guestbook is Synced and Healthy" \
    "$(jp -n argocd $app guestbook '{.status.sync.status} {.status.health.status}')" "Synced Healthy"
  check_match "Deployment guestbook-ui in $APP_NS is ready and managed by Argo CD" \
    "$(jp -n $APP_NS deploy guestbook-ui '{.status.readyReplicas} {.metadata.annotations.argocd\.argoproj\.io/tracking-id}')" "^1 guestbook:"
}

lab_cleanup() {
  # The Application has no finalizer: deleting it leaves the workload, the namespaces go anyway.
  kc -n argocd delete applications.argoproj.io guestbook --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kc delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=argocd --ignore-not-found >/dev/null
  kc delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found --wait=false >/dev/null
}
