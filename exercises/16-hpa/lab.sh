# shellcheck shell=bash
# Exercise 16 — Horizontal Pod Autoscaler. Sourced by scripts/lab.sh.
# kind ships without metrics-server: setup installs a pinned release with
# --kubelet-insecure-tls (kubelet serving certs on kind are self-signed).
LAB_CLUSTER=practice
NS=exercise-16
METRICS_SERVER_VERSION=v0.9.0
METRICS_SERVER_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  if ! exists -n kube-system deployment metrics-server; then
    log_info "Installing metrics-server ${METRICS_SERVER_VERSION}"
    kc apply -f "$METRICS_SERVER_URL"
    kc -n kube-system annotate deployment metrics-server cka-lab/installed-by=exercise-16 --overwrite
  fi
  if ! jp -n kube-system deployment metrics-server '{.spec.template.spec.containers[0].args}' | grep -q -- --kubelet-insecure-tls; then
    kc -n kube-system patch deployment metrics-server --type=json \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  fi
  kc -n kube-system rollout status deployment metrics-server --timeout=180s
}

lab_check() {
  local target='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}'
  local metric='{.spec.metrics[0].type} {.spec.metrics[0].resource.name} {.spec.metrics[0].resource.target.type} {.spec.metrics[0].resource.target.averageUtilization}'
  check_eq "Deployment load-app runs nginx:1.27" \
    "$(jp -n $NS deploy load-app '{.spec.template.spec.containers[0].image}')" "nginx:1.27"
  check_eq "load-app requests cpu 50m and is limited to cpu 100m" \
    "$(jp -n $NS deploy load-app '{.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.limits.cpu}')" \
    "50m 100m"
  check_match "load-app has at least one ready replica" "$(jp -n $NS deploy load-app '{.status.readyReplicas}')" "^[1-9]"
  check_eq "Service load-svc is a ClusterIP Service on port 80" \
    "$(jp -n $NS svc load-svc '{.spec.type} {.spec.ports[0].port}')" "ClusterIP 80"
  check_eq "Service load-svc selects the load-app pods (app=load-app)" \
    "$(jp -n $NS svc load-svc '{.spec.selector.app}')" "load-app"
  check_match "Service load-svc has endpoints" \
    "$(jp -n $NS endpointslices -l kubernetes.io/service-name=load-svc '{.items[*].endpoints[*].addresses[0]}')" "[0-9]"
  check_eq "HPA load-app targets Deployment load-app" "$(jp -n $NS hpa load-app "$target")" "Deployment/load-app"
  check_eq "HPA load-app scales between 1 and 5 replicas" \
    "$(jp -n $NS hpa load-app '{.spec.minReplicas}-{.spec.maxReplicas}')" "1-5"
  check_eq "HPA load-app uses Resource cpu, target type Utilization at 50%" \
    "$(jp -n $NS hpa load-app "$metric")" "Resource cpu Utilization 50"
  check_match "HPA load-app reads a current CPU utilization (metrics-server + requests work)" \
    "$(jp -n $NS hpa load-app '{.status.currentMetrics[0].resource.current.averageUtilization}')" "^[0-9]+$"
  check_match "HPA load-app has scaled at least once under load (status.lastScaleTime)" \
    "$(jp -n $NS hpa load-app '{.status.lastScaleTime}')" "^[0-9]{4}-"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  if [[ "$(jp -n kube-system deployment metrics-server '{.metadata.annotations.cka-lab/installed-by}')" == "exercise-16" ]]; then
    log_info "Removing metrics-server (installed by setup)"
    kc delete -f "$METRICS_SERVER_URL" --ignore-not-found
  fi
}
