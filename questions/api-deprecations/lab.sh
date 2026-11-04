# shellcheck shell=bash
# Old manifests with API versions removed long before v1.35. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=legacy-apps

lab_params() {
  echo "HPA_MAX=$(pick 4 5 6 8)"
  echo "CPU=$(pick 60 70 75 80)"
  echo "SCHEDULE=$(pick '*/30 * * * *' '15 2 * * *' '0 */6 * * *')"
}

_dir() { echo "$WORKDIR/legacy-apps"; }

lab_setup() {
  ensure_ns "$NS"
  mkdir -p "$(_dir)"
  cat >"$(_dir)/service.yaml" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: report-ui
  namespace: $NS
spec:
  selector:
    app: report-ui
  ports:
  - port: 80
YAML
  cat >"$(_dir)/deployment.yaml" <<YAML
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: report-ui
  namespace: $NS
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: report-ui
    spec:
      containers:
      - name: web
        image: nginx:1.28
        resources:
          requests:
            cpu: 50m
YAML
  cat >"$(_dir)/hpa.yaml" <<YAML
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: report-ui
  namespace: $NS
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: report-ui
  minReplicas: 2
  maxReplicas: $HPA_MAX
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: $CPU
YAML
  cat >"$(_dir)/cronjob.yaml" <<YAML
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: report-cleanup
  namespace: $NS
spec:
  schedule: "$SCHEDULE"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: cleanup
            image: busybox:1.37
            command: ["sh", "-c", "echo removing old reports"]
YAML
  cat >"$(_dir)/ingress.yaml" <<YAML
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: report-ui
  namespace: $NS
spec:
  rules:
  - host: reports.example.com
    http:
      paths:
      - path: /
        backend:
          serviceName: report-ui
          servicePort: 80
YAML
}

# _dry <file> -> 0 when the API server accepts the file as it is
_dry() { kc apply --dry-run=server -f "$(_dir)/$1"; }

lab_check() {
  local f
  check_gate "Deployment report-ui exists in namespace $NS" exists -n $NS deploy report-ui
  for f in deployment hpa cronjob ingress; do
    check "$(_dir)/$f.yaml is accepted by the API server (server dry-run)" _dry "$f.yaml"
  done
  check_eq "Deployment report-ui: selector app=report-ui, image nginx:1.28, 2 ready replicas" \
    "$(jp -n $NS deploy report-ui '{.spec.selector.matchLabels.app} {.spec.template.spec.containers[0].image} {.status.readyReplicas}')" \
    "report-ui nginx:1.28 2"
  check_eq "HPA report-ui scales Deployment report-ui between 2 and $HPA_MAX at $CPU% CPU" \
    "$(jp -n $NS hpa report-ui '{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name} {.spec.minReplicas}-{.spec.maxReplicas} {.spec.metrics[0].resource.name}={.spec.metrics[0].resource.target.averageUtilization}')" \
    "Deployment/report-ui 2-$HPA_MAX cpu=$CPU"
  check_eq "CronJob report-cleanup runs busybox:1.37 on schedule '$SCHEDULE'" \
    "$(jp -n $NS cronjob report-cleanup '{.spec.schedule}|{.spec.jobTemplate.spec.template.spec.containers[0].image}')" \
    "$SCHEDULE|busybox:1.37"
  local r='{.spec.rules[0]'
  check_eq "Ingress report-ui routes reports.example.com/ (Prefix) to Service report-ui:80" \
    "$(jp -n $NS ingress report-ui "$r.host}$r.http.paths[0].path} $r.http.paths[0].pathType} $r.http.paths[0].backend.service.name}:$r.http.paths[0].backend.service.port.number}")" \
    "reports.example.com/ Prefix report-ui:80"
  check_eq "Service report-ui exists" "$(jp -n $NS svc report-ui '{.spec.ports[0].port}')" "80"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
