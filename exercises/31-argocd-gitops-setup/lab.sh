# shellcheck shell=bash
# Exercise 31 — Argo CD via Helm template + a GitOps Application. Sourced by scripts/lab.sh.
# Setup pre-installs the Argo CD CRDs (as in the exam task: "the CRDs are already
# installed"); the user renders the chart WITHOUT CRDs, applies it and creates an Application.
LAB_CLUSTER=practice
NS=exercise-31
ARGOCD_VERSION=v3.5.6       # appVersion of chart argo-cd 10.11.6
CHART_VERSION=10.11.6
TEMPLATE_FILE="$HOME/argo-helm.yaml"
CRD_BASE="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/crds"

_no_crds() { test -s "$1" && ! grep -q "^kind: CustomResourceDefinition" "$1"; }

lab_setup() {
  local crd
  for crd in application appproject applicationset; do
    kc apply --server-side --force-conflicts -f "$CRD_BASE/${crd}-crd.yaml" >/dev/null
  done
  echo "  Argo CD $ARGOCD_VERSION CRDs installed: $(jp crd -l app.kubernetes.io/part-of=argocd '{range .items[*]}{.metadata.name} {end}')"
}

lab_check() {
  check "Template file $TEMPLATE_FILE exists" test -s "$TEMPLATE_FILE"
  check "$TEMPLATE_FILE contains the argocd-server Deployment" \
    grep -q "app.kubernetes.io/name: argocd-server" "$TEMPLATE_FILE"
  check "$TEMPLATE_FILE was rendered from chart argo-cd $CHART_VERSION" \
    grep -q "helm.sh/chart: argo-cd-$CHART_VERSION" "$TEMPLATE_FILE"
  check "$TEMPLATE_FILE contains no CustomResourceDefinition (crds.install=false)" \
    _no_crds "$TEMPLATE_FILE"

  local d
  for d in argocd-server argocd-repo-server argocd-redis argocd-dex-server argocd-applicationset-controller argocd-notifications-controller; do
    check_eq "Deployment $d in argocd is available" \
      "$(jp -n argocd deploy "$d" '{.status.conditions[?(@.type=="Available")].status}')" "True"
  done
  check_eq "StatefulSet argocd-application-controller has 1 ready replica" \
    "$(jp -n argocd sts argocd-application-controller '{.status.readyReplicas}')" "1"
  check_eq "argocd-server runs quay.io/argoproj/argocd:$ARGOCD_VERSION" \
    "$(jp -n argocd deploy argocd-server '{.spec.template.spec.containers[0].image}')" "quay.io/argoproj/argocd:$ARGOCD_VERSION"

  check_eq "Application guestbook in argocd uses repo argocd-example-apps, path guestbook" \
    "$(jp -n argocd application guestbook '{.spec.source.repoURL} {.spec.source.path}')" \
    "https://github.com/argoproj/argocd-example-apps.git guestbook"
  check_eq "Application guestbook deploys to the in-cluster API, namespace $NS" \
    "$(jp -n argocd application guestbook '{.spec.destination.server} {.spec.destination.namespace}')" \
    "https://kubernetes.default.svc $NS"
  check_eq "Application guestbook syncs automatically (prune + selfHeal)" \
    "$(jp -n argocd application guestbook '{.spec.syncPolicy.automated.prune} {.spec.syncPolicy.automated.selfHeal}')" "true true"
  check_eq "Application guestbook is Synced" "$(jp -n argocd application guestbook '{.status.sync.status}')" "Synced"
  check_eq "Application guestbook is Healthy" "$(jp -n argocd application guestbook '{.status.health.status}')" "Healthy"

  check_eq "Deployment guestbook-ui in $NS has 1 ready replica" "$(jp -n $NS deploy guestbook-ui '{.status.readyReplicas}')" "1"
  check_eq "Service guestbook-ui in $NS exposes port 80" "$(jp -n $NS svc guestbook-ui '{.spec.ports[0].port}')" "80"
  check_match "guestbook-ui is tracked by Argo CD application guestbook (annotation argocd.argoproj.io/tracking-id)" \
    "$(jp -n $NS deploy guestbook-ui '{.metadata.annotations.argocd\.argoproj\.io/tracking-id}')" "^guestbook:"
}

lab_cleanup() {
  # The Application has no finalizer, so deleting it leaves the workload: delete its namespace too.
  kc -n argocd delete application guestbook --ignore-not-found --wait=false 2>/dev/null || true
  kc delete namespace "$NS" argocd --ignore-not-found --wait=false
  kc delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=argocd --ignore-not-found
  kc delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found --wait=false
  rm -f "$TEMPLATE_FILE"
}
