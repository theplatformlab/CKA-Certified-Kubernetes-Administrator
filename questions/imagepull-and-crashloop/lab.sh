# shellcheck shell=bash
# ImagePullBackOff + CrashLoopBackOff. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=checkout
GATEWAY=http://gateway.checkout.svc:9000
PAY_CMD='test -n "$GATEWAY_URL" || { echo "FATAL: environment variable GATEWAY_URL is not set"; exit 1; }; mkdir -p /www && echo "payment ok, gateway $GATEWAY_URL" > /www/index.html && echo "payment listening on :8080" && exec httpd -f -p 8080 -h /www'

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cart
  template:
    metadata:
      labels:
        app: cart
    spec:
      containers:
      - name: cart
        image: nginx:1.28-alpline
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payment
  template:
    metadata:
      labels:
        app: payment
    spec:
      containers:
      - name: payment
        image: busybox:1.37
        command: ["sh", "-c", "$(printf '%s' "$PAY_CMD" | sed 's/["\\]/\\&/g')"]
        env:
        - name: GATEWAY_ULR
          value: $GATEWAY
        - name: LOG_LEVEL
          value: info
YAML
}

# Attempted: at least one of the two Deployments was changed.
_attempted() {
  [[ "$(jp -n $NS deploy cart '{.spec.template.spec.containers[0].image}')" != "nginx:1.28-alpline" ]] ||
    [[ -z "$(jp -n $NS deploy payment '{.spec.template.spec.containers[0].env[?(@.name=="GATEWAY_ULR")].name}')" ]]
}

lab_check() {
  local t='{.spec.template.spec.containers[0]'
  check_gate "At least one Deployment was fixed" _attempted
  check_eq "cart runs nginx:1.28-alpine" "$(jp -n $NS deploy cart "$t.image}")" "nginx:1.28-alpine"
  check_eq "cart has 2/2 updated, ready replicas" \
    "$(jp -n $NS deploy cart '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "2/2/2"
  check_eq "payment sets GATEWAY_URL=$GATEWAY" \
    "$(jp -n $NS deploy payment "$t.env[?(@.name==\"GATEWAY_URL\")].value}")" "$GATEWAY"
  check_eq "payment keeps LOG_LEVEL=info" \
    "$(jp -n $NS deploy payment "$t.env[?(@.name==\"LOG_LEVEL\")].value}")" "info"
  check_eq "payment keeps image busybox:1.37 and its command" \
    "$(jp -n $NS deploy payment "$t.image} $t.command[2]}")" "busybox:1.37 $PAY_CMD"
  check_eq "payment has 2/2 updated, ready replicas" \
    "$(jp -n $NS deploy payment '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "2/2/2"
  check_eq "The ready payment pods have not restarted" \
    "$(kc -n $NS get pods -l app=payment \
        -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==true)]}{.status.containerStatuses[0].restartCount}{" "}{end}' 2>/dev/null)" "0 0 "
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
