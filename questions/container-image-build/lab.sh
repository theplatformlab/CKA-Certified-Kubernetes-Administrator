# shellcheck shell=bash
# Build an image from a Dockerfile, save it as a tarball, run it in the cluster. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=build-pipeline

lab_params() {
  echo "VER=$(pick 1.4.2 2.0.1 1.7.0 3.1.5)"
  echo "BUILD=$(rand_suffix 8)"
}

_image() { echo "registry.local/greeter:$VER"; }
_tar() { echo "$WORKDIR/greeter-$VER.tar"; }

lab_setup() {
  ensure_ns "$NS"
  mkdir -p "$WORKDIR/greeter"
  cat >"$WORKDIR/greeter/Dockerfile" <<'DOCKERFILE'
FROM busybox:1.37
COPY index.html /www/index.html
EXPOSE 8080
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
DOCKERFILE
  echo "greeter $VER build $BUILD" >"$WORKDIR/greeter/index.html"
  rm -f "$(_tar)"
}

# _tar_refs -> the image names recorded in the tarball (docker-archive manifest.json or OCI index.json)
_tar_refs() {
  tar -xOf "$(_tar)" manifest.json 2>/dev/null
  tar -xOf "$(_tar)" index.json 2>/dev/null
}

# _nodes_with_image -> "<nodes with the image>/<all nodes>"
_nodes_with_image() {
  local node n=0 have=0
  for node in $(jp nodes '{.items[*].metadata.name}'); do
    n=$((n + 1))
    docker exec "$node" crictl images -o json 2>/dev/null \
      | jq -e --arg i "$(_image)" '[.images[].repoTags[]] | index($i)' >/dev/null 2>&1 && have=$((have + 1))
  done
  echo "$have/$n"
}

lab_check() {
  local t='{.spec.template.spec.containers[0]'
  check_gate "Image archive $(_tar) exists" test -s "$(_tar)"
  check_contains "The archive contains the image $(_image)" "$(_tar_refs)" "greeter:$VER"
  local nodes; nodes="$(_nodes_with_image)"
  check_eq "Image $(_image) is available on every node of the cluster" "${nodes%/*}" "${nodes#*/}"
  check_eq "Deployment greeter uses image $(_image)" "$(jp -n $NS deploy greeter "$t.image}")" "$(_image)"
  check_match "Deployment greeter never pulls the image from a registry (IfNotPresent or Never)" \
    "$(jp -n $NS deploy greeter "$t.imagePullPolicy}")" '^(IfNotPresent|Never)$'
  check_eq "Deployment greeter has 2 ready replicas" "$(jp -n $NS deploy greeter '{.spec.replicas}/{.status.readyReplicas}')" "2/2"
  check_eq "The pods serve the page built from $WORKDIR/greeter" \
    "$(kc -n $NS exec deploy/greeter -- wget -qO- -T 3 http://localhost:8080/ 2>/dev/null)" "greeter $VER build $BUILD"
}

lab_cleanup() {
  local node img; img="$(_image)"
  # Pods still using the image would keep it on the nodes.
  kc delete namespace "$NS" --ignore-not-found --timeout=90s >/dev/null 2>&1 || true
  for node in $(jp nodes '{.items[*].metadata.name}'); do
    docker exec "$node" crictl rmi "$img" >/dev/null 2>&1 || true
  done
  docker rmi "$img" >/dev/null 2>&1 || true
  command -v podman >/dev/null && podman rmi "$img" >/dev/null 2>&1
  rm -f "$(_tar)"
}
