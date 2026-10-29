# shellcheck shell=bash
# Logs of a crashed container. Sourced by scripts/lab.sh.
# The worker container crashes exactly once: a marker in an emptyDir (which
# survives container restarts) makes the second instance keep running, so the
# token is only in the logs of the previous instance.
LAB_CLUSTER=practice
NS=diag

lab_params() {
  echo "POD=$(pick payment-worker invoice-worker ledger-sync)"
  echo "TOKEN=tok-$(rand_suffix 10)"
  echo "ERR_CODE=$(rand_int 401 499)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
spec:
  terminationGracePeriodSeconds: 1
  containers:
  - name: worker
    image: busybox:1.37
    command:
    - sh
    - -c
    - |
      if [ -f /state/started ]; then
        echo "worker restarted after crash, waiting for operator"
        while true; do sleep 3600; done
      fi
      touch /state/started
      echo "starting $POD"
      echo "loading configuration from /etc/worker"
      echo "session token: $TOKEN"
      echo "connecting to ledger-db:5432"
      echo "FATAL: ledger-db:5432 refused the connection, giving up"
      exit 1
    volumeMounts:
    - name: state
      mountPath: /state
  volumes:
  - name: state
    emptyDir: {}
---
apiVersion: v1
kind: Pod
metadata:
  name: gateway
  namespace: $NS
  annotations:
    kubectl.kubernetes.io/default-container: proxy
spec:
  terminationGracePeriodSeconds: 1
  containers:
  - name: proxy
    image: busybox:1.37
    command:
    - sh
    - -c
    - |
      echo "INFO proxy listening on :8080"
      echo "ERROR upstream auth:9000 timed out"
      echo "INFO retrying upstream"
      echo "ERROR upstream auth:9000 timed out"
      while true; do sleep 3600; done
  - name: auth
    image: busybox:1.37
    command:
    - sh
    - -c
    - |
      echo "INFO auth service starting"
      echo "INFO loaded 3 signing keys"
      echo "ERROR token validation failed for client mobile-app: code $ERR_CODE"
      echo "WARN clock skew of 2s detected"
      echo "ERROR LDAP bind failed: invalid credentials for cn=svc-auth"
      echo "INFO health check ok"
      echo "ERROR token validation failed for client web-ui: code $ERR_CODE"
      echo "INFO health check ok"
      while true; do sleep 3600; done
YAML
  kc -n "$NS" wait --for=condition=Ready pod/gateway --timeout=120s
  local i
  for (( i = 0; i < 60; i++ )); do
    [[ "$(jp -n $NS pod "$POD" '{.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].ready}')" == "1 true" ]] && return 0
    sleep 2
  done
  log_error "Pod $POD did not restart as expected"
  return 1
}

lab_check() {
  local prev="$WORKDIR/previous.log" errs="$WORKDIR/auth-errors.log" expected
  check_gate "previous.log, token.txt or auth-errors.log exists" test -s "$prev" -o -s "$WORKDIR/token.txt" -o -s "$errs"
  check_contains "previous.log has the token line of the crashed instance" "$(cat "$prev" 2>/dev/null)" "session token: $TOKEN"
  check_contains "previous.log has the crash message (FATAL ...)" "$(cat "$prev" 2>/dev/null)" "FATAL: ledger-db:5432 refused the connection"
  check_not "previous.log does not contain the logs of the current instance" grep -q "restarted after crash" "$prev"
  check_eq "token.txt contains the token" "$(tr -d '[:space:]' 2>/dev/null <"$WORKDIR/token.txt")" "$TOKEN"
  expected="$(kc -n $NS logs gateway -c auth 2>/dev/null | grep ERROR)"
  check_eq "auth-errors.log has exactly the ERROR lines of container auth" \
    "$(sed 's/[[:space:]]*$//' "$errs" 2>/dev/null | grep -v '^$')" "${expected:-<no logs>}"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
