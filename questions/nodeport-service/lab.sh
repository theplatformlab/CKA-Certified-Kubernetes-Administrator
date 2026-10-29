# shellcheck shell=bash
# Expose an application with a NodePort. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=legacy

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: legacy-app
  template:
    metadata:
      labels:
        app: legacy-app
    spec:
      containers:
      - name: app
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && echo legacy-ok > /www/index.html && exec httpd -f -p 3000 -h /www"]
        ports:
        - containerPort: 3000
EOF
}

lab_check() {
  check_gate "Service legacy-svc exists" exists -n $NS svc legacy-svc
  check_eq "Type NodePort, port 8080 -> targetPort 3000, nodePort 30080" \
    "$(jp -n $NS svc legacy-svc '{.spec.type} {.spec.ports[0].port} {.spec.ports[0].targetPort} {.spec.ports[0].nodePort}')" \
    "NodePort 8080 3000 30080"
  check_eq "Service selects the legacy-app pods (app=legacy-app)" "$(jp -n $NS svc legacy-svc '{.spec.selector.app}')" "legacy-app"
  local ip; ip="$(jp node "$(worker_node 1)" '{.status.addresses[?(@.type=="InternalIP")].address}')"
  check_eq "The application answers on $ip:30080" \
    "$(probe default - "wget -qO- -T 5 http://$ip:30080" | tr -d '[:space:]')" "legacy-ok"
}
