# shellcheck shell=bash
# Harden a Dockerfile and its pod manifest. Sourced by scripts/lab.sh.
# Static checks of the two files in WORKDIR (nothing is built or deployed);
# the pod manifest is also sent as a server-side dry run into a namespace that
# enforces the restricted Pod Security Standard.
LAB_CLUSTER=practice
NS=report-gen

lab_params() {
  echo "API_TOKEN=sk-live-$(rand_suffix 24)"
}

lab_setup() {
  ensure_ns "$NS"
  kc label ns "$NS" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
  kc -n "$NS" create secret generic report-api --from-literal=token="$API_TOKEN" --dry-run=client -o yaml | kc apply -f -
  mkdir -p "$WORKDIR"
  cat >"$WORKDIR/app.py" <<'PY'
import os
import time

token = os.environ.get("API_TOKEN", "")
while True:
    print(f"generating report (token configured: {bool(token)})", flush=True)
    time.sleep(60)
PY
  cat >"$WORKDIR/Dockerfile" <<EOF
FROM ubuntu:latest
ENV API_TOKEN=$API_TOKEN
RUN apt-get update && apt-get install -y python3 python3-pip curl wget vim netcat-openbsd
COPY app.py /app/app.py
USER root
CMD ["python3", "/app/app.py"]
EOF
  cat >"$WORKDIR/pod.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: report-gen
  namespace: $NS
spec:
  containers:
  - name: app
    image: registry.example.com/report-gen:1.4.0
    env:
    - name: API_TOKEN
      value: $API_TOKEN
    securityContext:
      privileged: true
EOF
  cp "$WORKDIR/Dockerfile" "$WORKDIR/.Dockerfile.orig"
  cp "$WORKDIR/pod.yaml" "$WORKDIR/.pod.yaml.orig"
}

# _df -> the Dockerfile without comments and blank lines, continuation lines joined
_df() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$WORKDIR/Dockerfile" 2>/dev/null | sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta'; }
# _last <INSTRUCTION> -> arguments of its last occurrence
_last() { _df | grep -iE "^[[:space:]]*$1[[:space:]]" | tail -1 | sed -E "s/^[[:space:]]*$1[[:space:]]+//I; s/[[:space:]]+\$//"; }
# _pod <jq filter> -> from pod.yaml, parsed by kubectl (client side)
_pod() { kc create --dry-run=client -f "$WORKDIR/pod.yaml" -o json 2>/dev/null | jq -r "$1" 2>/dev/null; }

lab_check() {
  local from user
  check_gate "Dockerfile or pod.yaml was changed" bash -c "cd '$WORKDIR' && test -s Dockerfile && test -s pod.yaml &&
    ! { cmp -s Dockerfile .Dockerfile.orig && cmp -s pod.yaml .pod.yaml.orig; }"
  from="$(_last FROM)"
  check_match "Final stage is based on python:3.13-alpine" "$from" '^python:3\.13-alpine(@sha256:[0-9a-f]{64})?([[:space:]]+[Aa][Ss][[:space:]]+[A-Za-z0-9_-]+)?$'
  check_not "No extra packages are installed (apt-get, apk add, curl, wget, vim, netcat)" \
    grep -qiE 'apt-get|apk[[:space:]]+add|curl|wget|vim|netcat' <(_df)
  check_not "The API token is not baked into the image (no ENV/ARG API_TOKEN, no token value)" \
    grep -qE "API_TOKEN|$API_TOKEN" <(_df)
  user="$(_last USER)"
  check_match "The image runs as UID 10001" "$user" '^10001(:[0-9]+)?$'
  check "app.py is still copied to /app/app.py" grep -qE '^[[:space:]]*COPY[[:space:]]+(--[a-z]+=[^[:space:]]+[[:space:]]+)*app\.py[[:space:]]+/app/(app\.py)?$' <(_df)
  check_match "CMD still starts /app/app.py with python3" "$(_last CMD)" 'python3.*/app/app\.py'

  check_eq "pod.yaml: pod report-gen still runs registry.example.com/report-gen:1.4.0" \
    "$(_pod '.metadata.name + " " + .spec.containers[0].image')" "report-gen registry.example.com/report-gen:1.4.0"
  check_eq "pod.yaml: API_TOKEN comes from Secret report-api, key token" \
    "$(_pod '.spec.containers[0].env[]? | select(.name == "API_TOKEN") | .valueFrom.secretKeyRef.name + "/" + .valueFrom.secretKeyRef.key')" "report-api/token"
  check_not "pod.yaml: the token value is gone" grep -qF "$API_TOKEN" "$WORKDIR/pod.yaml"
  check_eq "pod.yaml: container is not privileged" "$(_pod '.spec.containers[0].securityContext.privileged // false')" "false"
  check_eq "pod.yaml: runs as non-root UID 10001" \
    "$(_pod '[(.spec.containers[0].securityContext.runAsNonRoot // .spec.securityContext.runAsNonRoot), (.spec.containers[0].securityContext.runAsUser // .spec.securityContext.runAsUser)] | map(tostring) | join(" ")')" "true 10001"
  check_eq "pod.yaml: root filesystem is read-only" "$(_pod '.spec.containers[0].securityContext.readOnlyRootFilesystem')" "true"
  check "pod.yaml is admitted in $NS (Pod Security restricted, server dry run)" \
    kc --request-timeout=10s -n "$NS" create --dry-run=server -f "$WORKDIR/pod.yaml"
}
