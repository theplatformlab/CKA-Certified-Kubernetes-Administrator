# shellcheck shell=bash
# Exercise 19 — Classic Ingress. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=exercise-19

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  # IngressClass "nginx" as an exam cluster would have it. No controller runs in the
  # lab cluster, so the Ingress gets no ADDRESS — the check validates the spec.
  if ! kc get ingressclass nginx >/dev/null 2>&1; then
    kc apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
  labels:
    cka-lab/exercise: "19"
spec:
  controller: k8s.io/ingress-nginx
EOF
  fi
}

# _path_backend <path> — "<pathType> <service>:<port>" of the rule path, across all rules.
_path_backend() {
  jp -n $NS ingress app-ingress \
    "{range .spec.rules[*].http.paths[?(@.path==\"$1\")]}{.pathType} {.backend.service.name}:{.backend.service.port.number}{end}"
}

lab_check() {
  local d
  for d in web-app api-app; do
    check_eq "Deployment $d runs nginx:1.28" "$(jp -n $NS deploy $d '{.spec.template.spec.containers[0].image}')" "nginx:1.28"
    check_eq "Deployment $d has 2 ready pods" "$(jp -n $NS deploy $d '{.spec.replicas}/{.status.readyReplicas}')" "2/2"
  done
  check_eq "Service web-service is ClusterIP, port 80 -> targetPort 80" \
    "$(jp -n $NS svc web-service '{.spec.type} {.spec.ports[0].port}->{.spec.ports[0].targetPort}')" "ClusterIP 80->80"
  check_eq "Service api-service is ClusterIP, port 8080 -> targetPort 80 (nginx listens on 80)" \
    "$(jp -n $NS svc api-service '{.spec.type} {.spec.ports[0].port}->{.spec.ports[0].targetPort}')" "ClusterIP 8080->80"
  check_match "web-service:80 and api-service:8080 both serve nginx" \
    "$(probe $NS - "wget -qO- -T 5 http://web-service.$NS.svc.cluster.local:80 2>/dev/null | grep -q 'Welcome to nginx' && echo web-ok; wget -qO- -T 5 http://api-service.$NS.svc.cluster.local:8080 2>/dev/null | grep -q 'Welcome to nginx' && echo api-ok" | tr '\n' ' ')" \
    "web-ok api-ok"

  check_eq "Ingress app-ingress uses IngressClass nginx" "$(jp -n $NS ingress app-ingress '{.spec.ingressClassName}')" "nginx"
  check_eq "Path / (Prefix) routes to web-service:80" "$(_path_backend /)" "Prefix web-service:80"
  check_eq "Path /api (Prefix) routes to api-service:8080" \
    "$(_path_backend /api)$(_path_backend /api/)" "Prefix api-service:8080"
  check_eq "Default backend is web-service:80" \
    "$(jp -n $NS ingress app-ingress '{.spec.defaultBackend.service.name}:{.spec.defaultBackend.service.port.number}')" "web-service:80"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  # Only delete the IngressClass if this lab created it.
  kc delete ingressclass -l cka-lab/exercise=19 --ignore-not-found
}
