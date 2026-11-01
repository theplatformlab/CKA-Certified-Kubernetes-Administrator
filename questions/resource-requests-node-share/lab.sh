# shellcheck shell=bash
# Size resource requests to fit a node. Sourced by scripts/lab.sh.
# kind nodes report the whole host's CPU/memory, so setup derives the "too high"
# requests from the node's real allocatable: 60% each, so only 1 of 3 replicas fits.
# The check recomputes each replica's fair share of what is free on the node.
LAB_CLUSTER=practice
NS=capacity

_node() { worker_node 1; }

# _milli <cpu quantity>  — CPU in millicores ("1", "1.5", "250m")
_milli() {
  awk -v q="$1" 'BEGIN { if (q ~ /m$/) { sub(/m$/, "", q); printf "%d", q } else printf "%d", q * 1000 }'
}

# _mib <memory quantity>  — memory in MiB ("128Mi", "1Gi", "1048576Ki", "500M", "134217728")
_mib() {
  awk -v q="$1" 'BEGIN {
    n = q; u = q; sub(/[A-Za-z]+$/, "", n); sub(/^[0-9.eE+-]+/, "", u)
    f["Ki"]=1024; f["Mi"]=1048576; f["Gi"]=1073741824; f["Ti"]=1099511627776
    f["k"]=1000; f["K"]=1000; f["M"]=1000000; f["G"]=1000000000; f["T"]=1000000000000; f[""]=1
    printf "%d", n * f[u] / 1048576 }'
}

# _free <cpu|memory>  — allocatable minus requests of all pods on the node except the web pods
_free() {
  local node res="$1" alloc used=0 q
  node="$(_node)"
  alloc="$(jp node "$node" "{.status.allocatable.$res}")"
  while read -r q; do
    [[ -z "$q" ]] && continue
    if [[ "$res" == cpu ]]; then used=$((used + $(_milli "$q"))); else used=$((used + $(_mib "$q"))); fi
  done < <(kc get pods -A --field-selector "spec.nodeName=$node,status.phase!=Succeeded,status.phase!=Failed" \
    -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.labels.app}{range .spec.containers[*]} {.resources.requests.'"$res"'}{end}{"\n"}{end}' \
    | awk -v skip="$NS/web" '$1 != skip { for (i = 2; i <= NF; i++) print $i }')
  if [[ "$res" == cpu ]]; then echo $(( $(_milli "$alloc") - used )); else echo $(( $(_mib "$alloc") - used )); fi
}

lab_setup() {
  local node cpu mem
  node="$(_node)"
  ensure_ns "$NS"
  cpu="$(( $(_milli "$(jp node "$node" '{.status.allocatable.cpu}')") * 6 / 10 ))m"
  mem="$(( $(_mib "$(jp node "$node" '{.status.allocatable.memory}')") * 6 / 10 ))Mi"
  kc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: $NS
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      nodeSelector:
        kubernetes.io/hostname: $node
      containers:
      - name: nginx
        image: nginx:1.27
        resources:
          requests:
            cpu: $cpu
            memory: $mem
EOF
  echo "  Deployment web requests cpu=$cpu memory=$mem per replica on $node."
}

lab_check() {
  local node cpu mem fcpu fmem
  node="$(_node)"
  # Untouched, only 1 of the 3 replicas fits on the node.
  check_gate "Deployment web has 3 ready replicas" \
    test "$(jp -n $NS deploy web '{.spec.replicas}/{.status.readyReplicas}/{.status.updatedReplicas}')" = "3/3/3"
  check_eq "web pods still run nginx:1.27 pinned to $node" \
    "$(jp -n $NS deploy web '{.spec.template.spec.containers[0].image} {.spec.template.spec.nodeSelector.kubernetes\.io/hostname}')" \
    "nginx:1.27 $node"
  cpu="$(jp -n $NS deploy web '{.spec.template.spec.containers[0].resources.requests.cpu}')"
  mem="$(jp -n $NS deploy web '{.spec.template.spec.containers[0].resources.requests.memory}')"
  check_match "web requests cpu and memory" "$cpu $mem" "^[^ ]+ [^ ]+$"
  [[ -n "$cpu" && -n "$mem" ]] || return 0
  fcpu=$(( $(_free cpu) / 3 ))
  fmem=$(( $(_free memory) / 3 ))
  check "CPU request $cpu is 75-100% of a third of the free CPU on $node (${fcpu}m)" \
    test "$(_milli "$cpu")" -ge $((fcpu * 75 / 100)) -a "$(_milli "$cpu")" -le "$fcpu"
  check "Memory request $mem is 75-100% of a third of the free memory on $node (${fmem}Mi)" \
    test "$(_mib "$mem")" -ge $((fmem * 75 / 100)) -a "$(_mib "$mem")" -le "$fmem"
}
