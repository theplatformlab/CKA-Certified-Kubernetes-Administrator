# shellcheck shell=bash
# In-place pod resize through the resize subresource. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="ml-training"
P=trainer

lab_params() {
  local cr cl mr ml
  read -r cr cl mr ml <<<"$(pick "500m 1 256Mi 512Mi" "400m 800m 192Mi 384Mi" "600m 1200m 256Mi 640Mi" "300m 750m 160Mi 320Mi")"
  echo "CPU_REQ=$cr"
  echo "CPU_LIM=$cl"
  echo "MEM_REQ=$mr"
  echo "MEM_LIM=$ml"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $P
  namespace: $NS
  labels:
    app: trainer
spec:
  containers:
  - name: trainer
    image: nginx:1.28
    resizePolicy:
    - resourceName: cpu
      restartPolicy: NotRequired
    - resourceName: memory
      restartPolicy: NotRequired
    resources:
      requests:
        cpu: 200m
        memory: 128Mi
      limits:
        cpu: 400m
        memory: 256Mi
YAML
  # Remember which pod this is: it must be resized, not replaced.
  kc annotate ns "$NS" --overwrite "cka-lab/trainer-uid=$(jp -n $NS pod $P '{.metadata.uid}')" >/dev/null
}

lab_check() {
  local r='{.spec.containers[0].resources' s='{.status.containerStatuses[0].resources'
  local want="$CPU_REQ/$CPU_LIM $MEM_REQ/$MEM_LIM"
  check_gate "Pod $P requests $CPU_REQ CPU" test "$(jp -n $NS pod $P "$r.requests.cpu}")" = "$CPU_REQ"
  check_eq "Pod $P is still the original pod (not deleted and recreated)" \
    "$(jp -n $NS pod $P '{.metadata.uid}')" "$(jp ns $NS '{.metadata.annotations.cka-lab/trainer-uid}')"
  check_eq "Spec: CPU $CPU_REQ/$CPU_LIM, memory $MEM_REQ/$MEM_LIM (request/limit)" \
    "$(jp -n $NS pod $P "$r.requests.cpu}/$r.limits.cpu} $r.requests.memory}/$r.limits.memory}")" "$want"
  check_eq "The kubelet has applied the new resources to the running container" \
    "$(jp -n $NS pod $P "$s.requests.cpu}/$s.limits.cpu} $s.requests.memory}/$s.limits.memory}")" "$want"
  check_eq "No resize is pending or in progress" \
    "$(jp -n $NS pod $P '{.status.conditions[?(@.type=="PodResizePending")].type}{.status.conditions[?(@.type=="PodResizeInProgress")].type}')" ""
  check_eq "Container trainer was not restarted and is ready" \
    "$(jp -n $NS pod $P '{.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].ready}')" "0 true"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
