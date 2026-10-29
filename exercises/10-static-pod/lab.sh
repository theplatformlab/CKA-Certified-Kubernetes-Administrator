# shellcheck shell=bash
# Exercise 10 — Static Pod. Sourced by scripts/lab.sh.
# The static pod runs on the worker node of the ops cluster.
LAB_CLUSTER=ops
NS="${ITEM_NS:-exercise-10}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
  echo "  Static pod node: $(worker_node)  (shell: docker exec -it $(worker_node) bash)"
}

lab_check() {
  local node mirror
  node="$(worker_node)"
  mirror="static-web-$node"

  check "Manifest /etc/kubernetes/manifests/static-web.yaml exists on $node" \
    node_exec "$node" "test -f /etc/kubernetes/manifests/static-web.yaml"
  check_not "No static-web manifest on the control plane (the pod belongs on $node)" \
    node_exec "$(control_plane_node)" "test -f /etc/kubernetes/manifests/static-web.yaml"

  check_eq "Mirror pod $mirror is owned by Node $node (it is a static pod)" \
    "$(jp -n $NS pod "$mirror" '{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" "Node/$node"
  check_eq "Pod $mirror has label app=static-web" "$(jp -n $NS pod "$mirror" '{.metadata.labels.app}')" "static-web"
  check_eq "Container web runs nginx:1.27" \
    "$(jp -n $NS pod "$mirror" '{.spec.containers[?(@.name=="web")].image}')" "nginx:1.27"
  check_eq "Container web exposes containerPort 80" \
    "$(jp -n $NS pod "$mirror" '{.spec.containers[?(@.name=="web")].ports[0].containerPort}')" "80"
  check_eq "Pod $mirror is Ready" \
    "$(jp -n $NS pod "$mirror" '{.status.conditions[?(@.type=="Ready")].status}')" "True"

  local ip
  ip="$(jp -n $NS pod "$mirror" '{.status.podIP}')"
  check "nginx answers on http://<pod IP>:80" probe "$NS" - "wget -qO- -T 5 http://${ip:-0.0.0.0}:80"
}

lab_cleanup() {
  node_exec "$(worker_node)" "rm -f /etc/kubernetes/manifests/static-web.yaml"
  node_exec "$(control_plane_node)" "rm -f /etc/kubernetes/manifests/static-web.yaml"
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
