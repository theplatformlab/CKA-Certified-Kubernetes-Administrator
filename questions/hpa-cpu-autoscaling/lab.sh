# shellcheck shell=bash
# HorizontalPodAutoscaler. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=autoscale

lab_params() {
  echo "HPA_MIN=$(pick 2 3)"
  echo "HPA_MAX=$(rand_int 6 12)"
  echo "CPU=$(pick 60 65 70 75 80)"
  echo "WINDOW=$(pick 30 60 120)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: $NS
spec:
  replicas: ${HPA_MIN}
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:1.28
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
EOF
}

lab_check() {
  local h="hpa.v2.autoscaling"
  check_eq "HPA web-app targets Deployment web-app" \
    "$(jp -n $NS $h web-app '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}')" "Deployment/web-app"
  check_eq "minReplicas $HPA_MIN, maxReplicas $HPA_MAX" \
    "$(jp -n $NS $h web-app '{.spec.minReplicas}-{.spec.maxReplicas}')" "$HPA_MIN-$HPA_MAX"
  check_eq "Average CPU utilization target is $CPU%" \
    "$(jp -n $NS $h web-app '{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}')" "$CPU"
  check_eq "Scale-down stabilization window is ${WINDOW}s" \
    "$(jp -n $NS $h web-app '{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" "$WINDOW"
}
