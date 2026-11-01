# shellcheck shell=bash
# gVisor (runsc) is installed on the worker with the containerd runtime
# handler "runsc" (init-cluster.sh --profile cks). Create the RuntimeClass and
# move a Deployment into the sandbox. Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
NS=sandboxed-apps

lab_params() {
  echo "RC=$(pick gvisor sandboxed untrusted)"
}

lab_setup() {
  if ! node_exec "$(worker_node 1)" "command -v runsc >/dev/null && grep -q 'runtimes.runsc\]' /etc/containerd/config.toml" 2>/dev/null; then
    log_error "gVisor is not installed on $(worker_node 1). Create the cluster with: ./scripts/init-cluster.sh --profile cks"
    return 1
  fi
  rm -f "$WORKDIR/gvisor-dmesg.txt"
  ensure_ns "$NS"
  kc apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: file-parser
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels: {app: file-parser}
  template:
    metadata:
      labels: {app: file-parser}
    spec:
      containers:
      - name: parser
        image: busybox:1.37
        command: ["sleep", "1d"]
YAML
  kc -n "$NS" rollout status deploy/file-parser --timeout=120s >/dev/null
}

lab_check() {
  local pods p bad=""
  check_gate "RuntimeClass $RC exists" exists runtimeclass "$RC"
  check_eq "RuntimeClass $RC uses the handler runsc" "$(jp runtimeclass "$RC" '{.handler}')" "runsc"
  check_eq "Deployment file-parser uses RuntimeClass $RC" "$(jp -n "$NS" deploy file-parser '{.spec.template.spec.runtimeClassName}')" "$RC"
  check_eq "Deployment file-parser has 2 ready replicas" "$(jp -n "$NS" deploy file-parser '{.status.readyReplicas}/{.status.updatedReplicas}')" "2/2"
  pods="$(kc -n "$NS" get pod -l app=file-parser --field-selector=status.phase=Running \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}} {{end}}{{end}}' 2>/dev/null)"
  for p in $pods; do
    kc -n "$NS" exec "$p" -- dmesg 2>/dev/null | grep -q gVisor || bad+="$p "
  done
  check_eq "The running file-parser Pods run in gVisor (dmesg)" "${pods:+${bad:-all}}" "all"
  check "gvisor-dmesg.txt has the dmesg output of a sandboxed Pod" grep -q 'Starting gVisor' "$WORKDIR/gvisor-dmesg.txt"
}

lab_cleanup() {
  kc delete runtimeclass "$RC" --ignore-not-found >/dev/null 2>&1 || true
  rm -f "$WORKDIR/gvisor-dmesg.txt"
}
