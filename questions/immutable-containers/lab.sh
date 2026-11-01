# shellcheck shell=bash
# Immutable containers. Sourced by scripts/lab.sh.
# Six standalone pods, four of them not immutable (privileged, writable root
# filesystem, a writable sidecar, runAsUser 0). tax-calc looks like root at pod
# level but its container overrides runAsUser, so it stays.
# invoice-web (nginx-unprivileged) needs a writable /tmp only.
LAB_CLUSTER=practice
NS=invoice-svc
BAD_PODS="mailer ledger-sync audit-shipper fx-rates"
GOOD_PODS="pdf-renderer tax-calc"

# _pod <name> <pod securityContext json> <containers yaml>
_pod() {
  kc apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: $NS
  labels:
    app: $1
spec:
  terminationGracePeriodSeconds: 1
  securityContext: $2
  containers:
$3
YAML
}

_ctr() { # <name> <securityContext json>
  printf '  - name: %s\n    image: busybox:1.37\n    command: ["sleep", "1d"]\n    securityContext: %s\n' "$1" "$2"
}

lab_setup() {
  ensure_ns "$NS"
  _pod pdf-renderer '{"runAsNonRoot": true, "runAsUser": 1000}' "$(_ctr renderer '{"readOnlyRootFilesystem": true, "allowPrivilegeEscalation": false}')"
  _pod mailer '{"runAsUser": 1000}' "$(_ctr mailer '{"readOnlyRootFilesystem": true, "privileged": true}')"
  _pod ledger-sync '{}' "$(_ctr sync '{}')"
  _pod tax-calc '{"runAsUser": 0}' "$(_ctr calc '{"runAsUser": 2000, "readOnlyRootFilesystem": true}')"
  _pod audit-shipper '{"runAsUser": 1000}' "$(_ctr shipper '{"readOnlyRootFilesystem": true}')
$(_ctr log-agent '{"readOnlyRootFilesystem": false}')"
  _pod fx-rates '{}' "$(_ctr rates '{"runAsUser": 0, "readOnlyRootFilesystem": true}')"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: invoice-web
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: invoice-web
  template:
    metadata:
      labels:
        app: invoice-web
    spec:
      containers:
      - name: nginx
        image: nginxinc/nginx-unprivileged:1.28-alpine
        ports:
        - containerPort: 8080
YAML
  kc -n "$NS" wait --for=condition=Ready pod --all --timeout=120s >/dev/null
  kc -n "$NS" rollout status deploy invoice-web --timeout=120s
}

# _mutable_pods — names of the (not terminating) pods with a container that is not immutable
_mutable_pods() {
  kc -n "$NS" get pods -o json 2>/dev/null | jq -r '
    .items[] | select(.metadata.deletionTimestamp == null) | . as $p
    | select(any(.spec.containers[];
        (.securityContext.runAsUser // $p.spec.securityContext.runAsUser) as $u
        | ((.securityContext.runAsNonRoot // $p.spec.securityContext.runAsNonRoot) == true) as $nr
        | ((.securityContext.readOnlyRootFilesystem == true)
           and ((.securityContext.privileged // false) == false)
           and (($u != null and $u != 0) or ($u == null and $nr))) | not))
    | .metadata.name' 2>/dev/null
}

lab_check() {
  local mutable p left=0 web pod
  mutable="$(_mutable_pods)"
  for p in $BAD_PODS; do grep -qx "$p" <<<"$mutable" && left=$((left + 1)); done
  check_gate "Task attempted (a mutable pod is gone, or invoice-web was changed)" \
    test "$left" -lt 4 -o "$(jp -n $NS deploy invoice-web '{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}')" = true
  for p in $BAD_PODS; do
    check_not "Pod $p (not immutable) is gone" grep -qx "$p" <<<"$mutable"
  done
  for p in $GOOD_PODS; do
    check "Immutable pod $p is still running" test "$(jp -n $NS pod "$p" '{.status.phase}')" = Running
  done
  check_not "No other pod outside invoice-web is mutable" \
    bash -c "grep -v '^invoice-web-' <<<'$mutable' | grep -q ."
  check_eq "invoice-web sets readOnlyRootFilesystem: true" \
    "$(jp -n $NS deploy invoice-web '{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}')" "true"
  check_eq "invoice-web mounts an emptyDir at /tmp" \
    "$(kc -n $NS get deploy invoice-web -o json 2>/dev/null | jq -r '.spec.template.spec as $s | $s.containers[0].volumeMounts[]? | select(.mountPath == "/tmp" or .mountPath == "/tmp/") | .name as $n | $s.volumes[]? | select(.name == $n) | has("emptyDir")')" "true"
  check_eq "invoice-web is rolled out and ready" \
    "$(jp -n $NS deploy invoice-web '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "2/2/2"
  pod="$(kc -n $NS get pods -l app=invoice-web -o json 2>/dev/null | jq -r '[.items[] | select(.metadata.deletionTimestamp == null and .status.phase == "Running")][0].metadata.name // empty')"
  check_match "invoice-web's root filesystem is mounted read-only" \
    "$([[ -n "$pod" ]] && kc -n $NS exec "$pod" -- grep ' / ' /proc/mounts 2>/dev/null | cut -c1-40)" '^overlay / [a-z]+ ro[ ,]'
  web="$(jp -n $NS pod "$pod" '{.status.podIP}')"
  check_eq "invoice-web still serves HTTP on port 8080" \
    "$([[ -n "$web" ]] && probe "$NS" - "wget -qO- -T 3 http://$web:8080 >/dev/null 2>&1 && echo OK" | tr -d '[:space:]')" "OK"
}
