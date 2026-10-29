# shellcheck shell=bash
# Exercise 14 — Kustomize base and overlay. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-14}"
# Your kustomization lives in the item's answer directory.
KDIR="$WORKDIR/kustomize-lab"

# _render <dir> <jsonpath> — render a kustomization; the jsonpath is applied to each object.
_render() {
  kc kustomize "$1" 2>/dev/null | kc create --dry-run=client -f - -o jsonpath="$2" 2>/dev/null
}

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  mkdir -p "$KDIR"
  echo "  Write your files under $KDIR/"
}

lab_check() {
  local f
  for f in base/deployment.yaml base/service.yaml base/kustomization.yaml overlays/staging/kustomization.yaml; do
    check "File kustomize-lab/$f exists" test -f "$KDIR/$f"
  done
  check_eq "Base renders Service app-svc and Deployment app with 1 replica" \
    "$(_render "$KDIR/base" '{.kind}/{.metadata.name}/{.spec.replicas} ')" \
    "Service/app-svc/ Deployment/app/1 "
  check_eq "Staging overlay renders both objects into $NS with 3 replicas" \
    "$(_render "$KDIR/overlays/staging" '{.kind}/{.metadata.name}/{.metadata.namespace}/{.spec.replicas} ')" \
    "Service/app-svc/$NS/ Deployment/app/$NS/3 "

  check_eq "Deployment app runs nginx:1.27" "$(jp -n $NS deploy app '{.spec.template.spec.containers[0].image}')" "nginx:1.27"
  check_eq "Deployment app has 3 replicas (patched by the overlay)" "$(jp -n $NS deploy app '{.spec.replicas}')" "3"
  check_eq "Deployment app has 3 ready pods" "$(jp -n $NS deploy app '{.status.readyReplicas}')" "3"
  check_eq "Deployment app carries label env=staging" "$(jp -n $NS deploy app '{.metadata.labels.env}')" "staging"
  check_eq "Pod template carries label env=staging" "$(jp -n $NS deploy app '{.spec.template.metadata.labels.env}')" "staging"
  check_eq "3 running pods with labels app=app,env=staging" \
    "$(kc get pods -n $NS -l app=app,env=staging --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')" "3"
  check_eq "Service app-svc is ClusterIP on port 80" \
    "$(jp -n $NS svc app-svc '{.spec.type}:{.spec.ports[0].port}')" "ClusterIP:80"
  check_eq "Service app-svc carries label env=staging" "$(jp -n $NS svc app-svc '{.metadata.labels.env}')" "staging"
  check_eq "Service app-svc has 3 endpoints" \
    "$(kc get endpointslices -n $NS -l kubernetes.io/service-name=app-svc -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}' 2>/dev/null)" "xxx"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  echo "  Your files in $KDIR/ are kept — delete them with: rm -rf $KDIR"
}
