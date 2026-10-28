# shellcheck shell=bash
# Exercise 07 — StatefulSet. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=exercise-07

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  check_eq "Service web is headless" "$(jp -n $NS svc web '{.spec.clusterIP}')" "None"
  check_eq "Service web selects app=web" "$(jp -n $NS svc web '{.spec.selector.app}')" "web"
  check_eq "Service web exposes port 80 named http" \
    "$(jp -n $NS svc web '{.spec.ports[0].name}:{.spec.ports[0].port}')" "http:80"

  check_eq "StatefulSet web uses serviceName web" "$(jp -n $NS sts web '{.spec.serviceName}')" "web"
  check_eq "StatefulSet web has 3 replicas" "$(jp -n $NS sts web '{.spec.replicas}')" "3"
  check_eq "StatefulSet web has 3 ready pods" "$(jp -n $NS sts web '{.status.readyReplicas}')" "3"
  check_eq "Container nginx runs nginx:1.28" \
    "$(jp -n $NS sts web '{.spec.template.spec.containers[?(@.name=="nginx")].image}')" "nginx:1.28"
  check_eq "Volume www is mounted at /usr/share/nginx/html" \
    "$(jp -n $NS sts web '{.spec.template.spec.containers[0].volumeMounts[?(@.name=="www")].mountPath}')" \
    "/usr/share/nginx/html"
  check_eq "volumeClaimTemplate www requests 1Gi ReadWriteOnce" \
    "$(jp -n $NS sts web '{.spec.volumeClaimTemplates[?(@.metadata.name=="www")].spec.resources.requests.storage} {.spec.volumeClaimTemplates[?(@.metadata.name=="www")].spec.accessModes[0]}')" \
    "1Gi ReadWriteOnce"

  local i
  for i in 0 1 2; do
    check_eq "PVC www-web-$i is Bound" "$(jp -n $NS pvc www-web-$i '{.status.phase}')" "Bound"
  done
  check_not "No replica beyond web-2 is left after scaling back" exists -n $NS pod web-3
  for i in 0 1 2; do
    check_eq "web-$i.web.$NS.svc.cluster.local serves 'web-$i'" \
      "$(probe $NS - "wget -qO- -T 5 web-$i.web.$NS.svc.cluster.local" | tr -d '[:space:]')" "web-$i"
  done
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
