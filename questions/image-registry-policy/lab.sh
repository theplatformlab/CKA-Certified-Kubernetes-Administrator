# shellcheck shell=bash
# Allow only images from trusted registries (ValidatingAdmissionPolicy). Sourced by scripts/lab.sh.
# The check sends server-side dry runs: admission policies run on them, but
# nothing is created and no image is pulled.
LAB_CLUSTER=practice
NS=retail-prod
POLICY=allowed-registries
BINDING=allowed-registries-binding

lab_params() {
  echo "REGISTRY=$(pick harbor.retail.example registry.corp.example:5000 images.shop-internal.example)"
}

lab_setup() {
  ensure_ns "$NS"
  kc -n "$NS" create deployment checkout --image=registry.k8s.io/pause:3.10 --dry-run=client -o yaml | kc apply -f -
  rm -f "$WORKDIR/rejected.txt"
}

# _admitted <namespace> <image> [init image] — a pod with these images passes admission (dry run)
_admitted() {
  local init=""
  [[ -n "${3:-}" ]] && init="
  initContainers:
  - name: init
    image: $3"
  kc --request-timeout=10s create --dry-run=server -f - >/dev/null 2>&1 <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: registry-check-$RANDOM
  namespace: $1
spec:$init
  containers:
  - name: app
    image: $2
YAML
}

lab_check() {
  local err
  check_gate "ValidatingAdmissionPolicy $POLICY exists" exists validatingadmissionpolicy "$POLICY"
  check_eq "Binding $BINDING uses policy $POLICY with action Deny" \
    "$(jp validatingadmissionpolicybinding "$BINDING" '{.spec.policyName} {.spec.validationActions}')" "$POLICY [\"Deny\"]"
  check "A pod with registry.k8s.io/pause:3.10 is admitted in $NS" _admitted "$NS" registry.k8s.io/pause:3.10
  check "A pod with $REGISTRY/shop/cart:2.4.1 is admitted in $NS" _admitted "$NS" "$REGISTRY/shop/cart:2.4.1"
  check_not "A pod with nginx:1.28 (Docker Hub) is rejected in $NS" _admitted "$NS" nginx:1.28
  check_not "A pod with docker.io/library/busybox:1.37 is rejected in $NS" _admitted "$NS" docker.io/library/busybox:1.37
  check_not "A pod with registry.k8s.io.evil.example/pause:3.10 is rejected in $NS" _admitted "$NS" registry.k8s.io.evil.example/pause:3.10
  check_not "A pod with an allowed container but an init container from Docker Hub is rejected" \
    _admitted "$NS" registry.k8s.io/pause:3.10 busybox:1.37
  check "Pods in other namespaces are not affected (nginx:1.28 in default)" _admitted default nginx:1.28
  check_not "Pod nginx-test does not exist in $NS" exists -n "$NS" pod nginx-test
  err="$(cat "$WORKDIR/rejected.txt" 2>/dev/null)"
  check_match "rejected.txt holds the rejection by $POLICY" "$err" "ValidatingAdmissionPolicy '$POLICY'.*denied"
}

lab_cleanup() {
  kc delete validatingadmissionpolicybinding "$BINDING" --ignore-not-found >/dev/null
  kc delete validatingadmissionpolicy "$POLICY" --ignore-not-found >/dev/null
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
