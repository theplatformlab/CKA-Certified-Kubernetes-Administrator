# shellcheck shell=bash
# Q9 — HorizontalPodAutoscaler
Q_CLUSTER=practice
NS=production

q_setup() {
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: $NS
spec:
  replicas: 2
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

q_check() {
  local h="hpa.v2.autoscaling"
  check_eq "HPA web-app targets Deployment web-app" \
    "$(jp -n $NS $h web-app '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}')" "Deployment/web-app"
  check_eq "minReplicas 2, maxReplicas 10" \
    "$(jp -n $NS $h web-app '{.spec.minReplicas}-{.spec.maxReplicas}')" "2-10"
  check_eq "Average CPU utilization target is 70%" \
    "$(jp -n $NS $h web-app '{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}')" "70"
  check_eq "Scale-down stabilization window is 30s" \
    "$(jp -n $NS $h web-app '{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" "30"
}
