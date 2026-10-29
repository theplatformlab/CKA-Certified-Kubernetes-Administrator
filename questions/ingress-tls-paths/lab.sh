# shellcheck shell=bash
# Ingress with TLS. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=api

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  labels:
    cka-lab/item: ingress-tls-paths
spec:
  controller: k8s.io/ingress-nginx
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.28
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: $NS
spec:
  selector:
    app: api
  ports:
  - port: 8080
    targetPort: 80
EOF
  local tmp; tmp="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=api.example.com" \
    -keyout "$tmp/tls.key" -out "$tmp/tls.crt" >/dev/null 2>&1
  kc -n "$NS" create secret tls api-tls-cert --cert="$tmp/tls.crt" --key="$tmp/tls.key" \
    --dry-run=client -o yaml | kc apply -f -
  rm -rf "$tmp"
}

_path() {
  jp -n $NS ingress api-ingress \
    "{.spec.rules[?(@.host==\"api.example.com\")].http.paths[?(@.path==\"$1\")].pathType} {.spec.rules[?(@.host==\"api.example.com\")].http.paths[?(@.path==\"$1\")].backend.service.name}:{.spec.rules[?(@.host==\"api.example.com\")].http.paths[?(@.path==\"$1\")].backend.service.port.number}"
}

lab_check() {
  check_eq "Ingress api-ingress uses IngressClass nginx" \
    "$(jp -n $NS ingress api-ingress '{.spec.ingressClassName}')" "nginx"
  check_eq "TLS for api.example.com uses Secret api-tls-cert" \
    "$(jp -n $NS ingress api-ingress '{.spec.tls[0].hosts[*]} {.spec.tls[0].secretName}')" "api.example.com api-tls-cert"
  check_eq "/api (Prefix) routes to api:8080" "$(_path /api)" "Prefix api:8080"
  check_eq "/health (Exact) routes to api:8080" "$(_path /health)" "Exact api:8080"
}

lab_cleanup() {
  kc delete ingressclass nginx -l cka-lab/item=ingress-tls-paths --ignore-not-found >/dev/null 2>&1 || true
}
