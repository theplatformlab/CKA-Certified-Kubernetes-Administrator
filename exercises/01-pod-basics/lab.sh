# shellcheck shell=bash
# Exercise 01 — Pod basics. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-01}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  check "Pod web exists in $NS" exists -n $NS pod web
  check_eq "Pod web runs image nginx:1.27" "$(jp -n $NS pod web '{.spec.containers[0].image}')" "nginx:1.27"
  check_eq "Pod web is Running and Ready" \
    "$(jp -n $NS pod web '{.status.phase}/{.status.conditions[?(@.type=="Ready")].status}')" "Running/True"
  check_eq "Requests: cpu 100m, memory 64Mi" \
    "$(jp -n $NS pod web '{.spec.containers[0].resources.requests.cpu} {.spec.containers[0].resources.requests.memory}')" \
    "100m 64Mi"
  check_eq "Limits: cpu 250m, memory 128Mi" \
    "$(jp -n $NS pod web '{.spec.containers[0].resources.limits.cpu} {.spec.containers[0].resources.limits.memory}')" \
    "250m 128Mi"
  check_eq "Label app=web" "$(jp -n $NS pod web '{.metadata.labels.app}')" "web"
  check_eq "Label version=v1 was added" "$(jp -n $NS pod web '{.metadata.labels.version}')" "v1"
  check_eq "Label tier was removed" "$(jp -n $NS pod web '{.metadata.labels.tier}')" ""
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
