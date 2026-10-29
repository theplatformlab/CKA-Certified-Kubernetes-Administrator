# shellcheck shell=bash
# Find resource-hungry pods with kubectl top. Sourced by scripts/lab.sh.
# kind ships without metrics-server: setup installs a pinned release with
# --kubelet-insecure-tls (kubelet serving certs on kind are self-signed).
# The ranking is deterministic: exactly one batch pod burns CPU (capped by a
# CPU limit) and exactly one fills a memory-backed emptyDir; the check compares
# the answers with that setup, not with live metrics.
LAB_CLUSTER=practice
NS=perf
METRICS_SERVER_VERSION=v0.9.0
METRICS_SERVER_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_SERVER_VERSION}/components.yaml"
POD_NAMES="ingest render report export"

lab_params() {
  local names c m
  read -ra names <<<"$POD_NAMES"
  c="$(rand_int 0 3)"
  m=$(( (c + $(rand_int 1 3)) % 4 ))
  echo "CPU_POD=${names[c]}"
  echo "MEM_POD=${names[m]}"
}

_install_metrics_server() {
  if ! exists -n kube-system deployment metrics-server; then
    log_info "Installing metrics-server ${METRICS_SERVER_VERSION}"
    kc apply -f "$METRICS_SERVER_URL" >/dev/null
    kc -n kube-system annotate deployment metrics-server cka-lab/installed-by=kubectl-top-usage --overwrite >/dev/null
  fi
  if ! jp -n kube-system deployment metrics-server '{.spec.template.spec.containers[0].args}' | grep -q -- --kubelet-insecure-tls; then
    kc -n kube-system patch deployment metrics-server --type=json \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  fi
  kc -n kube-system rollout status deployment metrics-server --timeout=180s
}

# _pod <name> <labels> <cpu-limit> <memory-limit> <command> [tmpfs-size]
_pod() {
  local name="$1" labels="$2" cpu="$3" mem="$4" cmd="$5" tmpfs="${6:-}" mount="" vol=""
  if [[ -n "$tmpfs" ]]; then
    mount="
    volumeMounts:
    - name: cache
      mountPath: /cache"
    vol="
  volumes:
  - name: cache
    emptyDir:
      medium: Memory
      sizeLimit: $tmpfs"
  fi
  kc apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels: {$labels}
spec:
  terminationGracePeriodSeconds: 1
  containers:
  - name: main
    image: busybox:1.37
    command: ["sh", "-c", "$cmd"]
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: $cpu
        memory: $mem$mount$vol
YAML
}

lab_setup() {
  ensure_ns "$NS"
  _install_metrics_server
  local idle="while true; do sleep 3600; done"
  local burn="while true; do :; done"
  local fill="dd if=/dev/zero of=/cache/fill bs=1M count=\$0 2>/dev/null; while true; do sleep 3600; done"
  local n
  for n in $POD_NAMES; do
    if [[ "$n" == "$CPU_POD" ]]; then
      _pod "$n" "app: batch" 200m 64Mi "$burn"
    elif [[ "$n" == "$MEM_POD" ]]; then
      _pod "$n" "app: batch" 100m 256Mi "${fill//\$0/160}" 200Mi
    else
      _pod "$n" "app: batch" 100m 64Mi "$idle"
    fi
  done
  # Busier than every batch pod, but not part of the selection.
  _pod noisy-neighbour "app: infra" 400m 400Mi "${fill//\$0/240} & $burn" 300Mi
  kc -n "$NS" wait --for=condition=Ready pod --all --timeout=120s
}

_answer() { tr -d '[:space:]' 2>/dev/null <"$WORKDIR/$1"; }

lab_check() {
  check_gate "cpu-pod.txt or mem-pod.txt exists" test -s "$WORKDIR/cpu-pod.txt" -o -s "$WORKDIR/mem-pod.txt"
  check_eq "cpu-pod.txt names the batch pod with the highest CPU usage" "$(_answer cpu-pod.txt)" "$CPU_POD"
  check_eq "mem-pod.txt names the batch pod with the highest memory usage" "$(_answer mem-pod.txt)" "$MEM_POD"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
  if [[ "$(jp -n kube-system deployment metrics-server '{.metadata.annotations.cka-lab/installed-by}')" == "kubectl-top-usage" ]]; then
    log_info "Removing metrics-server (installed by setup)"
    kc delete -f "$METRICS_SERVER_URL" --ignore-not-found >/dev/null
  fi
}
