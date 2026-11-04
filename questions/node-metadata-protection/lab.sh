# shellcheck shell=bash
# Block the cloud metadata endpoint with a NetworkPolicy. Sourced by scripts/lab.sh.
# kind has no cloud metadata service, so setup emulates one: 169.254.169.254 is
# added to the control plane's loopback, a hostNetwork busybox httpd there
# answers like an instance metadata service, and every other node routes the
# address to the control plane. (kindnet only enforces NetworkPolicies on
# forwarded traffic, so the endpoint must not live on the pod's own node:
# pods run on the workers, the emulator on the control plane.)
LAB_CLUSTER=practice
NS=fleet-sync
MD_IP=169.254.169.254
EMU=cloud-metadata-emulator

# _emulator_routes — the address on the control plane, routes on the other nodes (idempotent)
_emulator_routes() {
  local cp cpip n
  cp="$(control_plane_node)"
  cpip="$(jp node "$cp" '{.status.addresses[?(@.type=="InternalIP")].address}')"
  [[ -n "$cpip" ]] || return 1
  node_exec "$cp" "ip addr replace $MD_IP/32 dev lo"
  for n in $(kc get nodes -o name | sed 's|node/||'); do
    [[ "$n" == "$cp" ]] && continue
    node_exec "$n" "ip route replace $MD_IP/32 via $cpip"
  done
}

lab_setup() {
  _emulator_routes
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $EMU
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $EMU
  template:
    metadata:
      labels:
        app: $EMU
    spec:
      hostNetwork: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
      - operator: Exists
      terminationGracePeriodSeconds: 1
      containers:
      - name: httpd
        image: busybox:1.37
        command:
        - sh
        - -c
        - |
          d=/www/latest/meta-data/iam/security-credentials
          mkdir -p \$d
          echo i-0f3a9c2e81b7d4410 > /www/latest/meta-data/instance-id
          echo node-instance-role > \$d/index.html
          echo '{"AccessKeyId":"ASIAEXAMPLEFAKE","SecretAccessKey":"fake-not-a-real-key"}' > \$d/node-instance-role
          exec httpd -f -p $MD_IP:80 -h /www
YAML
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sync-api
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sync-api
  template:
    metadata:
      labels:
        app: sync-api
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: api
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /www && echo sync-api > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: sync-api
  namespace: $NS
spec:
  selector:
    app: sync-api
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-inventory
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: node-inventory
  template:
    metadata:
      labels:
        app: node-inventory
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: inventory
        image: busybox:1.37
        command: ["sh", "-c", "while true; do wget -qO- -T 3 http://$MD_IP/latest/meta-data/instance-id; sleep 30; done"]
YAML
  kc -n kube-system rollout status deploy "$EMU" --timeout=120s
  kc -n "$NS" rollout status deploy sync-api --timeout=120s
  kc -n "$NS" rollout status deploy node-inventory --timeout=120s
}

# _probe_all <labels> -> "md=OPEN|CLOSED dns=... api=... svc=..." from one throwaway pod
# (kindnet's policy agent learns a new pod's IP and labels with a short delay.)
_probe_all() {
  probe "$NS" "$1" "sleep 5
    t() { if \"\$@\" >/dev/null 2>&1; then echo OPEN; else echo CLOSED; fi; }
    echo md=\$(t wget -qO- -T 3 http://$MD_IP/latest/meta-data/instance-id) \
      dns=\$(t nslookup -timeout=3 kubernetes.default.svc.cluster.local) \
      api=\$(t wget -qO- -T 3 --no-check-certificate https://kubernetes.default.svc/version) \
      svc=\$(t wget -qO- -T 3 http://sync-api)"
}

# _field <output> <key>
_field() { sed -n "s/.*$2=\([A-Z]*\).*/\1/p" <<<"$1"; }

lab_check() {
  # (The emulator's node routes are gone after a cluster restart; put them back.)
  _emulator_routes >/dev/null 2>&1
  check_gate "NetworkPolicy deny-cloud-metadata exists in $NS" exists -n $NS networkpolicy deny-cloud-metadata
  check_eq "deny-cloud-metadata selects every pod of $NS" "$(jp -n $NS networkpolicy deny-cloud-metadata '{.spec.podSelector}')" "{}"
  check_eq "deny-cloud-metadata restricts Egress only (no Ingress isolation)" \
    "$(jp -n $NS networkpolicy deny-cloud-metadata '{.spec.policyTypes}')" '["Egress"]'
  check "NetworkPolicy allow-cloud-metadata exists in $NS" exists -n $NS networkpolicy allow-cloud-metadata
  check_eq "allow-cloud-metadata selects app=node-inventory" \
    "$(jp -n $NS networkpolicy allow-cloud-metadata '{.spec.podSelector.matchLabels.app}')" "node-inventory"
  local other inv
  if [[ -z "$CHECK_GATE" ]]; then
    other="$(_probe_all app=sync-client)"
    inv="$(_probe_all app=node-inventory)"
  fi
  check_eq "Pods of $NS cannot reach http://$MD_IP" "$(_field "$other" md)" "CLOSED"
  check_eq "Pods of $NS can still resolve cluster DNS names" "$(_field "$other" dns)" "OPEN"
  check_eq "Pods of $NS can still reach the API server Service" "$(_field "$other" api)" "OPEN"
  check_eq "Service sync-api is still reachable inside $NS" "$(_field "$other" svc)" "OPEN"
  check_eq "app=node-inventory pods can reach http://$MD_IP" "$(_field "$inv" md)" "OPEN"
}

lab_cleanup() {
  local n
  kc -n kube-system delete deployment "$EMU" --ignore-not-found --wait=false >/dev/null 2>&1
  for n in $(kc get nodes -o name | sed 's|node/||'); do
    node_exec "$n" "ip addr del $MD_IP/32 dev lo 2>/dev/null; ip route del $MD_IP/32 2>/dev/null; true"
  done
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
