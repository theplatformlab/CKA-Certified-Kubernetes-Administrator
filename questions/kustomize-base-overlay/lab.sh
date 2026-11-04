# shellcheck shell=bash
# Kustomize base and overlay. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=staging-apps
KDIR="$WORKDIR/kustomize-lab"

lab_params() {
  echo "REPLICAS=$(pick 2 3 4)"
}

# _render <dir> <jsonpath> — render a kustomization; the jsonpath is applied to each object.
_render() {
  kc kustomize "$1" 2>/dev/null | kc create --dry-run=client -f - -o jsonpath="$2" 2>/dev/null
}

lab_setup() {
  ensure_ns "$NS"
  rm -rf "$KDIR"
  mkdir -p "$KDIR"
}

lab_check() {
  check_gate "kustomize-lab/overlays/staging/kustomization.yaml exists" \
    test -f "$KDIR/overlays/staging/kustomization.yaml"
  check_eq "Base renders Service app-svc and Deployment app with 1 replica" \
    "$(_render "$KDIR/base" '{.kind}/{.metadata.name}/{.spec.replicas} ')" \
    "Service/app-svc/ Deployment/app/1 "
  check_not "Base sets no namespace and no env label" \
    bash -c "kubectl --context '$CTX' kustomize '$KDIR/base' | grep -Eq '^ *(namespace|env):'"
  check_eq "Staging overlay renders both objects into $NS, the Deployment with $REPLICAS replicas" \
    "$(_render "$KDIR/overlays/staging" '{.kind}/{.metadata.name}/{.metadata.namespace}/{.spec.replicas} ')" \
    "Service/app-svc/$NS/ Deployment/app/$NS/$REPLICAS "
  check_eq "Deployment app runs container nginx with nginx:1.28" \
    "$(jp -n $NS deploy app '{.spec.template.spec.containers[0].name} {.spec.template.spec.containers[0].image}')" "nginx nginx:1.28"
  check_eq "Deployment app, its selector and pod template carry env=staging" \
    "$(jp -n $NS deploy app '{.metadata.labels.env}/{.spec.selector.matchLabels.env}/{.spec.template.metadata.labels.env}')" "staging/staging/staging"
  check_eq "Deployment app has $REPLICAS/$REPLICAS ready replicas" \
    "$(jp -n $NS deploy app '{.spec.replicas}/{.status.readyReplicas}')" "$REPLICAS/$REPLICAS"
  check_eq "Service app-svc is ClusterIP on port 80, label and selector env=staging" \
    "$(jp -n $NS svc app-svc '{.spec.type}:{.spec.ports[0].port} {.metadata.labels.env}/{.spec.selector.env}')" "ClusterIP:80 staging/staging"
  check_eq "Service app-svc has $REPLICAS ready endpoints" \
    "$(kc get endpointslices -n $NS -l kubernetes.io/service-name=app-svc -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}x{end}' 2>/dev/null | wc -c | tr -d ' ')" "$REPLICAS"
}
