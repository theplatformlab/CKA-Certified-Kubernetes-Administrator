# shellcheck shell=bash
# Service of type LoadBalancer. Sourced by scripts/lab.sh.
# kind has no load balancer controller: setup starts cloud-provider-kind as a
# container on the host docker (it serves every kind cluster on the host and
# creates one envoy container per LoadBalancer Service on the cluster's network).
LAB_CLUSTER=practice
NS=edge-lb
CPK_IMAGE=registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0
CPK_NAME=cka-cloud-provider-kind
CPK_LABEL=io.x-k8s.cloud-provider-kind.cluster

lab_params() {
  echo "APP=$(pick storefront catalog checkout webshop)"
  echo "LB_PORT=$(pick 8080 8088 9000 9080)"
  echo "NODE_PORT=$(rand_int 30100 32700)"
}

# Docker network of the cluster's nodes (kind, or KIND_EXPERIMENTAL_DOCKER_NETWORK at creation).
_cluster_network() {
  docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$(control_plane_node)" | awk '{print $1}'
}

# Start cloud-provider-kind unless it already runs for this cluster's network.
# (It creates the load balancer containers on one network only, given by
# KIND_EXPERIMENTAL_DOCKER_NETWORK.)
_ensure_cpk() {
  local net cur running
  net="$(_cluster_network)"
  running="$(docker inspect -f '{{.State.Running}}' "$CPK_NAME" 2>/dev/null || true)"
  cur="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CPK_NAME" 2>/dev/null |
    sed -n 's/^KIND_EXPERIMENTAL_DOCKER_NETWORK=//p' || true)"
  [[ "$running" == true && "${cur:-kind}" == "$net" ]] && return 0
  if [[ -n "$running" ]]; then
    [[ "$running" == true ]] && log_warn "Restarting $CPK_NAME for docker network $net (was ${cur:-kind})"
    docker rm -f "$CPK_NAME" >/dev/null
  fi
  log_info "Starting cloud-provider-kind ($CPK_IMAGE) as container $CPK_NAME"
  docker run -d --name "$CPK_NAME" --restart unless-stopped --network host \
    -e KIND_EXPERIMENTAL_DOCKER_NETWORK="$net" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$CPK_IMAGE" --gateway-channel=disabled --enable-default-ingress=false >/dev/null
}

lab_setup() {
  ensure_ns "$NS"
  _ensure_cpk
  kc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $APP-html
  namespace: $NS
data:
  index.html: "$APP is served through the load balancer\n"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $APP
  template:
    metadata:
      labels:
        app: $APP
    spec:
      containers:
      - name: web
        image: nginx:1.28
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: $APP-html
EOF
  kc -n "$NS" rollout status deploy "$APP" --timeout=120s
}

_lb_ip() { jp -n $NS svc "$APP-lb" '{.status.loadBalancer.ingress[0].ip}'; }

lab_check() {
  local svc="$APP-lb" ip="" i
  check_gate "Service $svc exists" exists -n $NS svc "$svc"
  check_eq "Service $svc is of type LoadBalancer" "$(jp -n $NS svc "$svc" '{.spec.type}')" "LoadBalancer"
  check_eq "Port $LB_PORT/TCP forwards to targetPort 80 via nodePort $NODE_PORT" \
    "$(jp -n $NS svc "$svc" '{.spec.ports[0].port}/{.spec.ports[0].protocol} {.spec.ports[0].targetPort} {.spec.ports[0].nodePort}')" \
    "$LB_PORT/TCP 80 $NODE_PORT"
  check_eq "Service $svc has the 2 $APP pods as endpoints" \
    "$(jp -n $NS endpointslices -l kubernetes.io/service-name="$svc" '{.items[*].endpoints[*].addresses[0]}' | wc -w | tr -d ' ')" "2"
  if [[ "$(jp -n $NS svc "$svc" '{.spec.type}')" == LoadBalancer ]]; then
    for (( i = 0; i < 30; i++ )); do
      ip="$(_lb_ip)"; [[ -n "$ip" ]] && break; sleep 2
    done
  fi
  check_match "Service $svc has an external IP" "$ip" '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  check_eq "lb-ip.txt contains the external IP" "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/lb-ip.txt")" "${ip:-<none>}"
  # Ask from a node container: it sits on the same docker network as the load balancer.
  local body=""
  if [[ -n "$ip" ]]; then
    for (( i = 0; i < 10; i++ )); do
      body="$(node_exec "$(control_plane_node)" "curl -s -m 3 http://$ip:$LB_PORT/" 2>/dev/null)"
      [[ -n "$body" ]] && break; sleep 2
    done
  fi
  check_contains "http://<external-ip>:$LB_PORT/ answers with the $APP page" "$body" "$APP is served through the load balancer"
}

lab_cleanup() {
  # The load balancer finalizer needs the controller: delete the LB Services
  # while it runs, otherwise the namespace hangs in Terminating.
  if [[ -n "$(jp -n $NS svc '{.items[?(@.spec.type=="LoadBalancer")].metadata.name}')" ]]; then
    _ensure_cpk
    kc -n $NS delete svc --all --timeout=60s >/dev/null 2>&1 || true
    local s
    for s in $(jp -n $NS svc '{.items[*].metadata.name}'); do
      kc -n $NS patch svc "$s" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
    done
    docker ps -aq --filter "label=$CPK_LABEL=$CLUSTER" | while read -r c; do
      if [[ "$(docker inspect -f "{{index .Config.Labels \"io.x-k8s.cloud-provider-kind.loadbalancer.name\"}}" "$c")" == "$CLUSTER/$NS/"* ]]; then
        docker rm -f "$c" >/dev/null
      fi
    done
  fi
  kc delete namespace "$NS" --ignore-not-found --wait=false
  # Stop the controller unless it still serves load balancers of other Services/clusters.
  if [[ -n "$(docker ps -aq --filter name="^${CPK_NAME}\$")" && -z "$(docker ps -aq --filter "label=$CPK_LABEL")" ]]; then
    log_info "Stopping $CPK_NAME (no load balancers left)"
    docker rm -f "$CPK_NAME" >/dev/null
  fi
}
