# shellcheck shell=bash
# Install an operator chart with CRDs. Sourced by scripts/lab.sh.
# The local chart installs its CRD only with crds.enabled=true; the custom
# resource in WORKDIR can only be created once the CRD exists.
LAB_CLUSTER=practice
NS=snapshot-system
APP_NS=warehouse-db
CHART_SRC="$ITEM_DIR/files/snapshot-operator"
CRD=snapshotpolicies.backup.cka-lab.io

lab_params() {
  echo "RELEASE=$(pick snapshots snap-operator volume-snapshots)"
  echo "RETAIN=$(rand_int 5 14)"
}

lab_setup() {
  ensure_ns "$APP_NS"
  mkdir -p "$WORKDIR/charts"
  rm -rf "$WORKDIR/charts/snapshot-operator"
  cp -r "$CHART_SRC" "$WORKDIR/charts/snapshot-operator"
  cat >"$WORKDIR/nightly-snapshots.yaml" <<YAML
apiVersion: backup.cka-lab.io/v1alpha1
kind: SnapshotPolicy
metadata:
  name: nightly
  namespace: $APP_NS
spec:
  schedule: "30 1 * * *"
  volumeSelector:
    matchLabels:
      app: warehouse-db
YAML
}

_helm() { helm --kube-context "$CTX" "$@"; }

lab_check() {
  check_gate "Release $RELEASE is deployed in namespace $NS" \
    test "$(_helm -n $NS status "$RELEASE" -o json 2>/dev/null | jq -r .info.status)" = "deployed"
  check_eq "Release $RELEASE uses chart snapshot-operator" \
    "$(_helm -n $NS list -f "^$RELEASE\$" -o json 2>/dev/null | jq -r '.[0].chart')" "snapshot-operator-0.4.2"
  check_eq "Value crds.enabled is true" \
    "$(_helm -n $NS get values "$RELEASE" -a -o json 2>/dev/null | jq -r .crds.enabled)" "true"
  check_eq "CRD $CRD is established" \
    "$(jp crd $CRD '{.status.conditions[?(@.type=="Established")].status}')" "True"
  check_eq "CRD $CRD belongs to release $RELEASE" \
    "$(jp crd $CRD '{.metadata.annotations.meta\.helm\.sh/release-name}/{.metadata.annotations.meta\.helm\.sh/release-namespace}')" \
    "$RELEASE/$NS"
  check_eq "Deployment $RELEASE-controller has 1 ready replica" \
    "$(jp -n $NS deploy "$RELEASE-controller" '{.status.readyReplicas}')" "1"
  check_eq "SnapshotPolicy nightly in $APP_NS keeps $RETAIN snapshots" \
    "$(jp -n $APP_NS snapshotpolicies.backup.cka-lab.io nightly '{.spec.retainCount}')" "$RETAIN"
  check_eq "SnapshotPolicy nightly keeps its schedule and selector" \
    "$(jp -n $APP_NS snapshotpolicies.backup.cka-lab.io nightly '{.spec.schedule} {.spec.volumeSelector.matchLabels.app}')" \
    "30 1 * * * warehouse-db"
  check_eq "nightly-snapshots.yaml sets retainCount $RETAIN" \
    "$(kc create --dry-run=client -f "$WORKDIR/nightly-snapshots.yaml" -o jsonpath='{.spec.retainCount}' 2>/dev/null)" "$RETAIN"
  check "Chart files in $WORKDIR/charts/snapshot-operator are unchanged" \
    diff -r "$CHART_SRC" "$WORKDIR/charts/snapshot-operator"
}

lab_cleanup() {
  helm --kube-context "$CTX" -n "$NS" uninstall "$RELEASE" >/dev/null 2>&1 || true
  # The chart keeps its CRD on uninstall (helm.sh/resource-policy: keep).
  kc delete crd "$CRD" --ignore-not-found >/dev/null
}
