# shellcheck shell=bash
# Kustomize cleanup and an HPA per environment. Sourced by scripts/lab.sh.
# Setup copies a base with staging/prod overlays into WORKDIR and applies both.
# The ConfigMap removed from the config stays in the cluster until it is deleted:
# kubectl apply only creates and updates.
LAB_CLUSTER=practice
STAGING=bookstore-staging
PROD=bookstore-prod
KSRC="$ITEM_DIR/files/bookstore"
KDIR="$WORKDIR/bookstore"

lab_params() {
  echo "HPA_MIN=$(pick 2 3)"
  echo "HPA_MAX=$(rand_int 4 6)"
  echo "PROD_MAX=$(rand_int 8 12)"
  echo "CPU=$(pick 60 65 70 75 80)"
}

lab_setup() {
  rm -rf "$KDIR"
  cp -r "$KSRC" "$KDIR"
  local env
  for env in staging prod; do
    ensure_ns "bookstore-$env"
    kc apply -k "$KDIR/overlays/$env" >/dev/null
  done
  kc -n "$STAGING" rollout status deploy bookstore --timeout=120s
  kc -n "$PROD" rollout status deploy bookstore --timeout=120s
  echo "  The kustomization is in $KDIR/"
}

# _render <dir> <jsonpath> — render a kustomization; the jsonpath is applied to each object.
_render() {
  kc kustomize "$1" 2>/dev/null | kc create --dry-run=client -f - -o jsonpath="$2" 2>/dev/null
}

# _kinds <dir> — sorted kinds of the rendered objects ("" when the build fails)
_kinds() { _render "$1" '{.kind}{"\n"}' | sort | xargs; }

_hpa_spec() {
  jp -n "$1" hpa.v2.autoscaling bookstore \
    '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name} {.spec.minReplicas}-{.spec.maxReplicas} {.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}'
}

lab_check() {
  check_gate "HPA bookstore exists in $STAGING" exists -n $STAGING hpa bookstore
  check_eq "HPA in $STAGING: Deployment/bookstore, $HPA_MIN-$HPA_MAX replicas, CPU $CPU%" \
    "$(_hpa_spec $STAGING)" "Deployment/bookstore $HPA_MIN-$HPA_MAX $CPU"
  check_eq "HPA in $PROD: Deployment/bookstore, $HPA_MIN-$PROD_MAX replicas, CPU $CPU%" \
    "$(_hpa_spec $PROD)" "Deployment/bookstore $HPA_MIN-$PROD_MAX $CPU"
  local ns
  for ns in $STAGING $PROD; do
    check_not "ConfigMap promo-config no longer exists in $ns" exists -n "$ns" configmap promo-config
    check_eq "Deployment bookstore in $ns does not use promo-config" \
      "$(jp -n "$ns" deploy bookstore '{.spec.template.spec.containers[*].envFrom[*].configMapRef.name}{.spec.template.spec.volumes[*].configMap.name}')" ""
    check_eq "Deployment bookstore in $ns has all replicas ready" \
      "$(jp -n "$ns" deploy bookstore '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" \
      "$(jp -n "$ns" deploy bookstore '{.spec.replicas}/{.spec.replicas}/{.spec.replicas}')"
  done
  check_eq "base renders Deployment, HPA and Service (no ConfigMap)" \
    "$(_kinds "$KDIR/base")" "Deployment HorizontalPodAutoscaler Service"
  check_eq "base HPA has maxReplicas $HPA_MAX" \
    "$(_render "$KDIR/base" '{.spec.maxReplicas}')" "$HPA_MAX"
  check_not "No file under bookstore/ refers to promo-config any more" grep -rq promo-config "$KDIR"
  local env max
  for env in staging prod; do
    max=$HPA_MAX; [[ $env == prod ]] && max=$PROD_MAX
    check_eq "overlays/$env renders Deployment, HPA and Service (no ConfigMap)" \
      "$(_kinds "$KDIR/overlays/$env")" "Deployment HorizontalPodAutoscaler Service"
    check_eq "overlays/$env HPA has maxReplicas $max" \
      "$(_render "$KDIR/overlays/$env" '{.spec.maxReplicas}')" "$max"
  done
}

lab_cleanup() {
  echo "  Your files in $KDIR/ are kept — delete them with: rm -rf $KDIR"
}
