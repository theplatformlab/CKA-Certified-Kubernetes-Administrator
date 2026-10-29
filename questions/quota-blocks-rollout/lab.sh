# shellcheck shell=bash
# Rollout stuck because the ResourceQuota is exhausted. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=billing

lab_params() {
  echo "REPLICAS=$(pick 4 5)"
  echo "CPU_REQ=$(pick 150m 200m)"
}

# The quota fits REPLICAS pods at 250m, but not at 300m. Printed the way the API stores it.
_quota_cpu() {
  local m=$((REPLICAS * 250))
  if (( m % 1000 == 0 )); then echo "$((m / 1000))"; else echo "${m}m"; fi
}

_deploy() {
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: invoice-api
  namespace: $NS
spec:
  replicas: $REPLICAS
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: invoice-api
  template:
    metadata:
      labels:
        app: invoice-api
    spec:
      containers:
      - name: api
        image: nginx:1.28
        resources:
          requests:
            cpu: $1
            memory: 64Mi
          limits:
            memory: 128Mi
YAML
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: v1
kind: ResourceQuota
metadata:
  name: billing-quota
  namespace: $NS
spec:
  hard:
    requests.cpu: "$(_quota_cpu)"
    requests.memory: 1Gi
    limits.memory: 2Gi
YAML
  _deploy 300m
}

lab_check() {
  local c='{.spec.template.spec.containers[0]'
  local cpu; cpu="$(jp -n $NS deploy invoice-api "$c.resources.requests.cpu}")"
  check_gate "CPU request of invoice-api was changed" test -n "$cpu" -a "$cpu" != "300m"
  check_eq "ResourceQuota billing-quota is unchanged" \
    "$(jp -n $NS resourcequota billing-quota '{.spec.hard.requests\.cpu} {.spec.hard.requests\.memory} {.spec.hard.limits\.memory}')" \
    "$(_quota_cpu) 1Gi 2Gi"
  check_eq "invoice-api requests cpu $CPU_REQ" "$(jp -n $NS deploy invoice-api "$c.resources.requests.cpu}")" "$CPU_REQ"
  check_eq "invoice-api keeps image and memory settings" \
    "$(jp -n $NS deploy invoice-api "$c.image} $c.resources.requests.memory} $c.resources.limits.memory}")" "nginx:1.28 64Mi 128Mi"
  check_eq "Rollout complete: $REPLICAS/$REPLICAS replicas updated and ready" \
    "$(jp -n $NS deploy invoice-api '{.spec.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}/{.status.replicas}')" \
    "$REPLICAS/$REPLICAS/$REPLICAS/$REPLICAS"
  check_eq "Every invoice-api pod requests cpu $CPU_REQ" \
    "$(kc -n $NS get pods -l app=invoice-api -o jsonpath='{range .items[*]}{.spec.containers[0].resources.requests.cpu}{"\n"}{end}' 2>/dev/null | sort -u)" \
    "$CPU_REQ"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
