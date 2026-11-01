# shellcheck shell=bash
# Add startup/liveness/readiness probes to a slow-starting Deployment. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=health-api

lab_params() {
  echo "PORT=$(pick 8080 8081 9090 3000)"
  echo "LIVE_PERIOD=$(pick 10 15 20)"
  echo "START_FAIL=$(pick 12 20 30)"
}

lab_setup() {
  ensure_ns "$NS"
  local cmd="echo starting orders-api; sleep 15; mkdir -p /www; echo ok > /www/healthz; touch /tmp/ready; echo listening on :$PORT; exec httpd -f -p $PORT -h /www"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orders-api
  template:
    metadata:
      labels:
        app: orders-api
    spec:
      containers:
      - name: api
        image: busybox:1.37
        command: ["sh", "-c", "$cmd"]
        ports:
        - containerPort: $PORT
YAML
}

lab_check() {
  local c='{.spec.template.spec.containers[0]'
  check_gate "orders-api has a startup, a liveness and a readiness probe" \
    test -n "$(jp -n $NS deploy orders-api "$c.startupProbe}")" -a -n "$(jp -n $NS deploy orders-api "$c.livenessProbe}")" \
    -a -n "$(jp -n $NS deploy orders-api "$c.readinessProbe}")"
  check_eq "Startup probe: TCP port $PORT, every 5s, failureThreshold $START_FAIL" \
    "$(jp -n $NS deploy orders-api "$c.startupProbe.tcpSocket.port} $c.startupProbe.periodSeconds} $c.startupProbe.failureThreshold}")" \
    "$PORT 5 $START_FAIL"
  check_eq "Liveness probe: HTTP GET /healthz on port $PORT, every ${LIVE_PERIOD}s, timeout 2s, failureThreshold 3" \
    "$(jp -n $NS deploy orders-api "$c.livenessProbe.httpGet.path} $c.livenessProbe.httpGet.port} $c.livenessProbe.periodSeconds} $c.livenessProbe.timeoutSeconds} $c.livenessProbe.failureThreshold}")" \
    "/healthz $PORT $LIVE_PERIOD 2 3"
  check_match "Readiness probe: exec 'cat /tmp/ready', every 5s" \
    "$(jp -n $NS deploy orders-api "$c.readinessProbe.exec.command[*]} $c.readinessProbe.periodSeconds}")" '^((/bin/)?sh -c )?cat /tmp/ready 5$'
  check_eq "Image and command are unchanged" \
    "$(jp -n $NS deploy orders-api "$c.image} $c.command[1]}")" "busybox:1.37 -c"
  check_eq "All 2 replicas are updated and ready" \
    "$(jp -n $NS deploy orders-api '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "2/2/2"
  check_eq "No container of orders-api has been restarted" \
    "$(jp -n $NS pods -l app=orders-api '{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | sort -u | tr -d '\n')" "0"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
