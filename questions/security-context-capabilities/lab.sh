# shellcheck shell=bash
# Pod and container securityContext: users, fsGroup, capabilities, read-only root. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=hardened-apps

lab_params() {
  echo "RUN_UID=$(pick 1000 2000 10001 4242)"
  echo "RUN_GID=$(pick 3000 3500 4000)"
  echo "FS_GID=$(pick 5000 6000 7000 8000)"
  echo "CAP=$(pick NET_ADMIN SYS_TIME NET_BIND_SERVICE)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: invoice-api
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: invoice-api
  template:
    metadata:
      labels:
        app: invoice-api
    spec:
      containers:
      - name: api
        image: busybox:1.37
        command: ["sh", "-c", "mkdir -p /tmp/www && echo invoice-api-ok > /tmp/www/index.html && echo 'invoice-api serving /tmp/www on :8080' && exec httpd -f -p 8080 -h /tmp/www"]
        ports:
        - containerPort: 8080
YAML
}

# _capbnd -> expected CapBnd of a process that has only $CAP
_capbnd() {
  local bit
  case "$CAP" in NET_BIND_SERVICE) bit=10 ;; NET_ADMIN) bit=12 ;; SYS_TIME) bit=25 ;; esac
  printf '%016x' $((1 << bit))
}

lab_check() {
  local p='{.spec.template.spec.securityContext' c='{.spec.template.spec.containers[0]'
  check_gate "Pod security context of invoice-api sets runAsUser $RUN_UID" \
    test "$(jp -n $NS deploy invoice-api "$p.runAsUser}")" = "$RUN_UID"
  check_eq "Pod security context: runAsGroup $RUN_GID, fsGroup $FS_GID, runAsNonRoot true" \
    "$(jp -n $NS deploy invoice-api "$p.runAsGroup} $p.fsGroup} $p.runAsNonRoot}")" "$RUN_GID $FS_GID true"
  check_eq "Container: allowPrivilegeEscalation false, readOnlyRootFilesystem true" \
    "$(jp -n $NS deploy invoice-api "$c.securityContext.allowPrivilegeEscalation} $c.securityContext.readOnlyRootFilesystem}")" "false true"
  check_eq "Container capabilities: drop ALL, add only $CAP" \
    "$(jp -n $NS deploy invoice-api "$c.securityContext.capabilities.drop[*]}|$c.securityContext.capabilities.add[*]}")" "ALL|$CAP"
  local tmpvol
  tmpvol="$(jp -n $NS deploy invoice-api "$c.volumeMounts[?(@.mountPath==\"/tmp\")].name}")"
  check_eq "An emptyDir volume is mounted at /tmp" \
    "$(jp -n $NS deploy invoice-api "{.spec.template.spec.volumes[?(@.name==\"${tmpvol:-none}\")].emptyDir}")" "{}"
  check_eq "Image and command are unchanged" \
    "$(jp -n $NS deploy invoice-api "$c.image} $c.command[2]}")" \
    "busybox:1.37 mkdir -p /tmp/www && echo invoice-api-ok > /tmp/www/index.html && echo 'invoice-api serving /tmp/www on :8080' && exec httpd -f -p 8080 -h /tmp/www"
  check_eq "All 2 replicas are updated and ready" \
    "$(jp -n $NS deploy invoice-api '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "2/2/2"
  # One exec for all runtime facts, as key=value lines.
  local out
  out="$(kc -n $NS exec deploy/invoice-api -- sh -c 'echo "ids=$(id -u) $(id -g)"; echo "groups=$(id -G)"
    echo "tmp=$(stat -c %g /tmp)"; echo "cap=$(grep CapBnd /proc/1/status | cut -f2)"
    echo "root=$(awk '"'"'$2=="/" {print $4}'"'"' /proc/mounts)"; echo "page=$(wget -qO- -T 3 localhost:8080)"' 2>/dev/null)"
  _val() { sed -n "s/^$1=//p" <<<"$out"; }
  check_eq "The process runs as uid $RUN_UID, gid $RUN_GID" "$(_val ids)" "$RUN_UID $RUN_GID"
  check_match "The process has supplementary group $FS_GID and /tmp belongs to it" "$(_val groups) /tmp:$(_val tmp)" "(^| )$FS_GID( .*)? /tmp:$FS_GID$"
  check_eq "The process has no capability but $CAP" "$(_val cap)" "$(_capbnd)"
  check_eq "The root filesystem is mounted read-only" "$(_val root | cut -d, -f1)" "ro"
  check_eq "The application still answers on port 8080" "$(_val page)" "invoice-api-ok"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
