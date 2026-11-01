# shellcheck shell=bash
# Downward API: env from fieldRef/resourceFieldRef and a downwardAPI volume. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=fleet-info
P=reporter

lab_params() {
  echo "TEAM=$(pick payments search checkout identity)"
  echo "MEM=$(pick 64 96 128 160)"
}

lab_setup() { ensure_ns "$NS"; }

lab_check() {
  local e='{.spec.containers[0].env[?(@.name=='
  check_gate "Pod $P exists" exists -n $NS pod $P
  check_eq "Pod $P: image busybox:1.37, labels app=reporter team=$TEAM, memory limit ${MEM}Mi" \
    "$(jp -n $NS pod $P '{.spec.containers[0].image} {.metadata.labels.app} {.metadata.labels.team} {.spec.containers[0].resources.limits.memory}')" \
    "busybox:1.37 reporter $TEAM ${MEM}Mi"
  check_eq "POD_NAME, POD_NAMESPACE, NODE_NAME, POD_IP come from fieldRefs" \
    "$(jp -n $NS pod $P "$e\"POD_NAME\")].valueFrom.fieldRef.fieldPath} $e\"POD_NAMESPACE\")].valueFrom.fieldRef.fieldPath} $e\"NODE_NAME\")].valueFrom.fieldRef.fieldPath} $e\"POD_IP\")].valueFrom.fieldRef.fieldPath}")" \
    "metadata.name metadata.namespace spec.nodeName status.podIP"
  check_eq "MEM_LIMIT_MI comes from resourceFieldRef limits.memory with divisor 1Mi" \
    "$(jp -n $NS pod $P "$e\"MEM_LIMIT_MI\")].valueFrom.resourceFieldRef.resource} $e\"MEM_LIMIT_MI\")].valueFrom.resourceFieldRef.divisor}")" \
    "limits.memory 1Mi"
  check_eq "Volume podinfo is a downwardAPI volume mounted at /etc/podinfo" \
    "$(jp -n $NS pod $P '{.spec.volumes[?(@.name=="podinfo")].downwardAPI.items[*].path} {.spec.containers[0].volumeMounts[?(@.name=="podinfo")].mountPath}')" \
    "labels annotations /etc/podinfo"
  check_eq "Pod $P is Ready" "$(jp -n $NS pod $P '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  local out
  out="$(kc -n $NS exec $P -- sh -c 'echo "env=$POD_NAME $POD_NAMESPACE $NODE_NAME $POD_IP $MEM_LIMIT_MI"; echo "labels=$(grep ^team= /etc/podinfo/labels)"' 2>/dev/null)"
  check_eq "The container sees its name, namespace, node, IP and memory limit" \
    "$(sed -n 's/^env=//p' <<<"$out")" "$P $NS $(jp -n $NS pod $P '{.spec.nodeName} {.status.podIP}') $MEM"
  check_eq "/etc/podinfo/labels contains team=\"$TEAM\"" "$(sed -n 's/^labels=//p' <<<"$out")" "team=\"$TEAM\""
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
