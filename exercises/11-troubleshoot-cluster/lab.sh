# shellcheck shell=bash
# Exercise 11 — Troubleshoot cluster components. Sourced by scripts/lab.sh.
# Setup breaks four things at once (scenarios A-D in the README); the check
# reports each scenario separately so they can be fixed in any order.
#   A  worker kubelet stopped and disabled
#   B  typo in the cluster domain of the CoreDNS Corefile
#   C  invalid proxy mode in the kube-proxy ConfigMap (Service web created afterwards has no rules)
#   D  audit logging enabled; a ServiceAccount is denied deleting Secret db-credentials
LAB_CLUSTER=ops
NS=exercise-11
APISERVER=/etc/kubernetes/manifests/kube-apiserver.yaml
AUDIT_LOG=/var/log/kubernetes/audit/audit.log
ANSWER=/opt/exercise-11/denied-user.txt
MARK="# cka-lab-11"

_kc() { kc --request-timeout=5s "$@"; }
_api_up() { _kc get --raw /readyz >/dev/null 2>&1; }

_wait_api() {  # _wait_api up|down <seconds>
  local i
  for ((i = 0; i < $2; i += 3)); do
    if [[ "$1" == up ]] && _api_up; then return 0; fi
    if [[ "$1" == down ]] && ! _api_up; then return 0; fi
    sleep 3
  done
  return 1
}

# Users that tried to delete Secret db-credentials in $NS and got 403, from the audit log.
_denied_users() {
  node_exec "$(control_plane_node)" "cat $AUDIT_LOG* 2>/dev/null | jq -r 'select(.verb==\"delete\" and .objectRef.resource==\"secrets\" and .objectRef.namespace==\"$NS\" and .objectRef.name==\"db-credentials\" and .responseStatus.code==403) | .user.username' 2>/dev/null | sort -u"
}

# --- Scenario D: enable audit logging on the API server ---------------------
_setup_audit() {
  local cp
  cp="$(control_plane_node)"
  if ! node_exec "$cp" "grep -q -- '$MARK' $APISERVER"; then
    node_exec "$cp" "mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [\"RequestReceived\"]
rules:
- level: None
  users: [\"system:kube-proxy\", \"system:kube-scheduler\", \"system:kube-controller-manager\", \"system:apiserver\"]
- level: None
  userGroups: [\"system:nodes\"]
- level: None
  nonResourceURLs: [\"/healthz*\", \"/livez*\", \"/readyz*\", \"/version\"]
- level: Metadata
EOF
cp $APISERVER /tmp/kube-apiserver.yaml.new
sed -i '/^    - kube-apiserver\$/a\\
    $MARK begin\\
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml\\
    - --audit-log-path=$AUDIT_LOG\\
    - --audit-log-maxsize=20\\
    - --audit-log-maxbackup=2\\
    $MARK end' /tmp/kube-apiserver.yaml.new
sed -i '/^    volumeMounts:\$/a\\
    $MARK begin\\
    - mountPath: /etc/kubernetes/audit\\
      name: audit-policy\\
      readOnly: true\\
    - mountPath: /var/log/kubernetes/audit\\
      name: audit-log\\
    $MARK end' /tmp/kube-apiserver.yaml.new
sed -i '/^  volumes:\$/a\\
  $MARK begin\\
  - hostPath:\\
      path: /etc/kubernetes/audit\\
      type: DirectoryOrCreate\\
    name: audit-policy\\
  - hostPath:\\
      path: /var/log/kubernetes/audit\\
      type: DirectoryOrCreate\\
    name: audit-log\\
  $MARK end' /tmp/kube-apiserver.yaml.new
mv /tmp/kube-apiserver.yaml.new $APISERVER"
    echo "  Restarting the API server with audit logging ..."
    sleep 5
    _wait_api up 180 || { log_error "API server did not come back — see crictl ps -a on $cp"; return 1; }
  fi

  kc -n "$NS" create secret generic db-credentials --from-literal=password=s3cr3t \
    --dry-run=client -o yaml | kc apply -f -
  local sa
  for sa in report-reader ci-deployer backup-agent; do
    kc -n "$NS" create serviceaccount "$sa" --dry-run=client -o yaml | kc apply -f -
  done
  kc -n "$NS" create role read-config --verb=get,list --resource=configmaps --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" create rolebinding read-config --role=read-config \
    --serviceaccount="$NS:report-reader" --serviceaccount="$NS:ci-deployer" --serviceaccount="$NS:backup-agent" \
    --dry-run=client -o yaml | kc apply -f -

  # Generate audit events once: allowed noise, a red herring and the denied delete.
  if [[ -n "$(_denied_users)" ]]; then return 0; fi
  local names=(report-reader ci-deployer backup-agent) culprit other api="https://127.0.0.1:6443/api/v1/namespaces/$NS"
  culprit="${names[RANDOM % 3]}"
  for sa in "${names[@]}"; do [[ "$sa" != "$culprit" ]] && other="$sa"; done
  _as() {  # _as <sa> <method> <path>
    local token
    token="$(kc -n "$NS" create token "$1" --duration=10m)"
    node_exec "$cp" "curl -sk --max-time 10 -o /dev/null -X $2 -H 'Authorization: Bearer $token' $api/$3"
  }
  for sa in "${names[@]}"; do _as "$sa" GET configmaps; done
  _as "$other" GET secrets/db-credentials      # denied read: red herring
  _as "$culprit" DELETE secrets/db-credentials # denied delete: the answer
  _as "$culprit" GET configmaps
}

_cleanup_audit() {
  local cp
  cp="$(control_plane_node)"
  if node_exec "$cp" "grep -q -- '$MARK' $APISERVER"; then
    node_exec "$cp" "sed '/$MARK begin/,/$MARK end/d' $APISERVER > /tmp/kube-apiserver.yaml.new && mv /tmp/kube-apiserver.yaml.new $APISERVER"
    echo "  Audit logging removed from the API server; waiting for it to restart ..."
    sleep 5
    _wait_api up 180 || log_warn "API server not ready yet — give it a minute"
  fi
  node_exec "$cp" "rm -rf /etc/kubernetes/audit /var/log/kubernetes/audit /opt/exercise-11"
}

lab_setup() {
  local cp worker
  cp="$(control_plane_node)"
  worker="$(worker_node)"
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -

  # D first: it restarts the API server.
  _setup_audit

  # Backend for scenario C (needs the worker, so before A).
  kc -n "$NS" create deployment web --image=nginx:1.27 --port=80 --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" rollout status deployment web --timeout=120s

  # C: kube-proxy can no longer start; Service web is created afterwards, so it gets no rules.
  if ! exists -n "$NS" service web; then
    kc -n kube-system get configmap kube-proxy -o yaml | sed 's/^    mode: .*/    mode: iptable/' | kc replace -f -
    kc -n kube-system delete pod -l k8s-app=kube-proxy --wait=false
    local i
    for ((i = 0; i < 40; i++)); do
      [[ "$(jp -n kube-system ds kube-proxy '{.status.numberReady}')" == 0 ]] && break
      sleep 3
    done
    kc -n "$NS" expose deployment web --port=80
  fi

  # B: CoreDNS serves the wrong cluster domain.
  if [[ "$(jp -n kube-system configmap coredns '{.data.Corefile}')" == *"kubernetes cluster.local "* ]]; then
    kc -n kube-system get configmap coredns -o yaml \
      | sed 's/kubernetes cluster\.local /kubernetes cluster.lcoal /' | kc replace -f -
    kc -n kube-system rollout restart deployment coredns
    kc -n kube-system rollout status deployment coredns --timeout=120s
  fi

  # A: kubelet on the worker is stopped and will not start on boot.
  node_exec "$worker" "systemctl disable --now kubelet" >/dev/null 2>&1
  echo "  Waiting for $worker to turn NotReady ..."
  local n
  for ((n = 0; n < 40; n++)); do
    [[ "$(jp node "$worker" '{.status.conditions[?(@.type=="Ready")].status}')" != True ]] && break
    sleep 3
  done

  echo "  Cluster broken (scenarios A-D). Nodes: docker exec -it $cp bash | docker exec -it $worker bash"
}

lab_check() {
  local cp worker
  cp="$(control_plane_node)"
  worker="$(worker_node)"

  if ! _api_up; then
    check "API server answers /readyz" false
    echo "      All scenarios need the API server — fix it first."
    return
  fi

  echo "  Scenario A — node $worker"
  check_eq "[A] Node $worker is Ready" \
    "$(jp --request-timeout=5s node "$worker" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "[A] kubelet is active on $worker" "$(node_exec "$worker" "systemctl is-active kubelet")" "active"
  check_eq "[A] kubelet is enabled on $worker (survives a reboot)" "$(node_exec "$worker" "systemctl is-enabled kubelet")" "enabled"

  local ready_nodes
  ready_nodes="$(jp --request-timeout=5s node "$worker" '{.status.conditions[?(@.type=="Ready")].status}')"

  echo "  Scenario B — DNS"
  check_match "[B] CoreDNS Corefile serves the cluster.local zone" \
    "$(jp --request-timeout=5s -n kube-system configmap coredns '{.data.Corefile}' | grep -E '^\s*kubernetes ' | sed 's/^ *//')" \
    '^kubernetes cluster\.local( |$)'
  check_eq "[B] Deployment coredns has all replicas ready" \
    "$(jp --request-timeout=5s -n kube-system deploy coredns '{.status.readyReplicas}/{.spec.replicas}')" \
    "$(jp --request-timeout=5s -n kube-system deploy coredns '{.spec.replicas}/{.spec.replicas}')"
  if [[ "$ready_nodes" == True ]]; then
    check "[B] A pod resolves kubernetes.default.svc.cluster.local" \
      probe "$NS" - "nslookup -timeout=3 kubernetes.default.svc.cluster.local"
  else
    check "[B] A pod resolves kubernetes.default.svc.cluster.local (skipped: no schedulable node, fix A first)" false
  fi

  echo "  Scenario C — Service web"
  check_eq "[C] kube-proxy is ready on every node" \
    "$(jp --request-timeout=5s -n kube-system ds kube-proxy '{.status.numberReady}/{.status.desiredNumberScheduled}')" \
    "$(jp --request-timeout=5s -n kube-system ds kube-proxy '{.status.desiredNumberScheduled}/{.status.desiredNumberScheduled}')"
  local ip
  ip="$(jp --request-timeout=5s -n "$NS" svc web '{.spec.clusterIP}')"
  if [[ "$ready_nodes" == True && -n "$ip" ]]; then
    check "[C] Service web answers on its ClusterIP ($ip:80)" probe "$NS" - "wget -qO- -T 5 http://$ip:80"
  else
    check "[C] Service web answers on its ClusterIP (skipped: no schedulable node or no Service web)" false
  fi

  echo "  Scenario D — audit log"
  local expected answer
  expected="$(_denied_users | head -1)"
  answer="$(node_exec "$cp" "cat $ANSWER 2>/dev/null" | tr -d '[:space:]')"
  check "[D] $ANSWER exists on $cp" node_exec "$cp" "test -s $ANSWER"
  if [[ -n "$expected" ]]; then
    # No check_eq here: its failure message would print the answer.
    check "[D] $ANSWER holds the full username that was denied deleting Secret db-credentials" \
      test "$answer" == "$expected"
  else
    check "[D] Audit log still contains the denied delete (rerun setup if the log is gone)" false
  fi
}

lab_cleanup() {
  local worker
  worker="$(worker_node)"
  node_exec "$worker" "systemctl enable --now kubelet" >/dev/null 2>&1 || true

  if [[ "$(jp -n kube-system configmap coredns '{.data.Corefile}')" == *"kubernetes cluster.lcoal "* ]]; then
    kc -n kube-system get configmap coredns -o yaml \
      | sed 's/kubernetes cluster\.lcoal /kubernetes cluster.local /' | kc replace -f -
    kc -n kube-system rollout restart deployment coredns
  fi
  if [[ "$(jp -n kube-system configmap kube-proxy '{.data.config\.conf}')" == *$'\nmode: iptable\n'* ]]; then
    kc -n kube-system get configmap kube-proxy -o yaml | sed 's/^    mode: iptable$/    mode: iptables/' | kc replace -f -
    kc -n kube-system delete pod -l k8s-app=kube-proxy --wait=false
  fi

  _cleanup_audit
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
