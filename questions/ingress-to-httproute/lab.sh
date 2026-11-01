# shellcheck shell=bash
# Migrate an Ingress to an HTTPRoute. Sourced by scripts/lab.sh.
# No controller runs for the GatewayClass, so the check evaluates the HTTPRoute
# rules itself: it routes sample requests by the Gateway API matching rules
# (path, then header precedence) and compares the chosen backends.
LAB_CLUSTER=practice
NS=media-hub
GATEWAY_API_VERSION=v1.6.3
GATEWAY_API_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
GW_CLASS=media-hub-class

lab_params() {
  echo "PREVIEW_PATH=$(pick /preview /beta /labs)"
  echo "HEADER=$(pick X-Beta-Tester X-Early-Access X-Preview-Group)"
  echo "HEADER_VALUE=$(pick yes enabled internal)"
}

_web() {
  kc -n $NS create deployment "$1" --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f - >/dev/null
  kc -n $NS create service clusterip "$1" --tcp="$2:80" --dry-run=client -o yaml | kc apply -f - >/dev/null
}

lab_setup() {
  ensure_ns "$NS"
  echo "  Installing Gateway API ${GATEWAY_API_VERSION} standard CRDs"
  kc apply --server-side -f "$GATEWAY_API_URL" >/dev/null
  kc wait --for=condition=Established --timeout=60s \
    crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
    crd/httproutes.gateway.networking.k8s.io >/dev/null
  _web player-ui 80
  _web player-ui-next 80
  _web media-api 8080
  cat >"$WORKDIR/media-ingress.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: media
  namespace: $NS
spec:
  ingressClassName: nginx
  rules:
  - host: media.example.com
    http:
      paths:
      - path: /watch
        pathType: Prefix
        backend:
          service:
            name: player-ui
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: media-api
            port:
              number: 8080
YAML
  kc apply -f "$WORKDIR/media-ingress.yaml" >/dev/null
  kc apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: $GW_CLASS
spec:
  controllerName: example.com/media-hub-gateway-controller
  description: Practice GatewayClass (no controller running)
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: media-gateway
  namespace: $NS
spec:
  gatewayClassName: $GW_CLASS
  listeners:
  - name: http
    protocol: HTTP
    port: 80
YAML
}

# _route <path> <headers as JSON object> — backends ("name:port", sorted) of the rule
# of HTTPRoute media-route that wins for a GET request; empty when no rule matches.
# Precedence as in the spec: Exact path, longest prefix, method, most header
# matches, most query matches, then rule order.
_route() {
  jq -r --arg path "$1" --argjson hdr "$2" '
    def pathok: (.type // "PathPrefix") as $t | (.value // "/") as $v
      | if $t == "Exact" then $path == $v
        elif $t == "PathPrefix" then ($v | rtrimstr("/")) as $b | $b == "" or $path == $b or ($path | startswith($b + "/"))
        else $path | test($v) end;
    def headersok: all(.headers[]?; (.name | ascii_downcase) as $n | $hdr[$n] as $h
      | $h != null and (if (.type // "Exact") == "Exact" then $h == .value else $h | test(.value) end));
    [ .spec.rules // [] | to_entries[] | .key as $i | .value as $r
      | ($r.matches // [{}])[]
      | select((.path // {}) | pathok) | select(headersok) | select((.method // "GET") == "GET")
      | select((.queryParams // []) | length == 0)
      | { score: [ (if .path.type == "Exact" then 1 else 0 end), ((.path.value // "/") | length),
                   (if .method then 1 else 0 end), (.headers // [] | length), -$i ],
          backends: [ $r.backendRefs[]? | select((.weight // 1) > 0) | "\(.name):\(.port)" ] | sort | join(" ") } ]
    | if length == 0 then "" else max_by(.score).backends end' <<<"$ROUTE_JSON" 2>/dev/null
}

lab_check() {
  local rt=httproutes.gateway.networking.k8s.io
  check_gate "HTTPRoute media-route exists in $NS" exists -n $NS $rt media-route
  ROUTE_JSON="$(kc -n $NS get $rt media-route -o json 2>/dev/null)"
  check_match "HTTPRoute media-route has media-gateway (namespace $NS or omitted) as parent" \
    "$(jp -n $NS $rt media-route '{.spec.parentRefs[0].name}/{.spec.parentRefs[0].namespace}')" "^media-gateway/($NS)?$"
  check_eq "HTTPRoute media-route serves hostname media.example.com" \
    "$(jp -n $NS $rt media-route '{.spec.hostnames[*]}')" "media.example.com"
  local h; h="$(tr '[:upper:]' '[:lower:]' <<<"$HEADER")"
  check_eq "/watch goes to player-ui:80" "$(_route /watch '{}')" "player-ui:80"
  check_eq "/watch/live/42 goes to player-ui:80" "$(_route /watch/live/42 '{}')" "player-ui:80"
  check_eq "/api/videos goes to media-api:8080" "$(_route /api/videos '{}')" "media-api:8080"
  check_eq "$PREVIEW_PATH with $HEADER: $HEADER_VALUE goes to player-ui-next:80" \
    "$(_route "$PREVIEW_PATH" "{\"$h\":\"$HEADER_VALUE\"}")" "player-ui-next:80"
  check_eq "$PREVIEW_PATH/home with $HEADER: $HEADER_VALUE goes to player-ui-next:80" \
    "$(_route "$PREVIEW_PATH/home" "{\"$h\":\"$HEADER_VALUE\"}")" "player-ui-next:80"
  check_eq "$PREVIEW_PATH without the header goes to player-ui:80" "$(_route "$PREVIEW_PATH" '{}')" "player-ui:80"
  check_eq "$PREVIEW_PATH with $HEADER: other goes to player-ui:80" \
    "$(_route "$PREVIEW_PATH" "{\"$h\":\"other\"}")" "player-ui:80"
  check_eq "/api/videos with $HEADER: $HEADER_VALUE still goes to media-api:8080" \
    "$(_route /api/videos "{\"$h\":\"$HEADER_VALUE\"}")" "media-api:8080"
  check_eq "Ingress media is unchanged" \
    "$(jp -n $NS ingress media '{.spec.rules[0].host} {range .spec.rules[0].http.paths[*]}{.path}={.backend.service.name}:{.backend.service.port.number} {end}')" \
    "media.example.com /watch=player-ui:80 /api=media-api:8080 "
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=true --timeout=120s >/dev/null || true
  kc delete gatewayclass "$GW_CLASS" --ignore-not-found >/dev/null
  # Remove the CRDs only if nothing else in the cluster still uses them.
  if kc get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    if [[ -z "$(kc get gatewayclasses,gateways,httproutes -A --no-headers 2>/dev/null)" ]]; then
      kc delete -f "$GATEWAY_API_URL" --ignore-not-found >/dev/null || true
      echo "  Removed Gateway API CRDs"
    else
      echo "  Gateway API CRDs kept: other Gateway API objects still exist"
    fi
  fi
}
