# shellcheck shell=bash
# Install a Localhost seccomp profile on a worker and use it in a Pod; move a
# Deployment from Unconfined to RuntimeDefault. Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
NS=fintech-core
SECCOMP_DIR=/var/lib/kubelet/seccomp

lab_params() {
  echo "PROFILE=$(pick deny-mkdir no-mkdir block-mkdir)"
  echo "POD=$(pick hardened locked-down audit-worker)"
}

lab_setup() {
  local w; w="$(worker_node 1)"
  node_exec_stdin "$w" "mkdir -p /root/profiles && cat > /root/profiles/$PROFILE.json" <<'JSON'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": ["mkdir", "mkdirat"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
JSON
  ensure_ns "$NS"
  kc apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-api
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels: {app: legacy-api}
  template:
    metadata:
      labels: {app: legacy-api}
    spec:
      securityContext:
        seccompProfile:
          type: Unconfined
      containers:
      - name: api
        image: busybox:1.37
        command: ["sleep", "1d"]
YAML
  kc -n "$NS" rollout status deploy/legacy-api --timeout=120s >/dev/null
}

# _pod_profile <jsonpath of a pod spec> <kc get args> -> "pod:<type>/<profile>" and one "c:<type>/<profile>" line per container
_pod_profile() {
  local spec="$1"
  echo "pod:$(jp -n "$NS" "${@:2}" "{$spec.securityContext.seccompProfile.type}/{$spec.securityContext.seccompProfile.localhostProfile}")"
  jp -n "$NS" "${@:2}" "{range $spec.containers[*]}c:{.securityContext.seccompProfile.type}/{.securityContext.seccompProfile.localhostProfile}{\"\\n\"}{end}"
}

# _effective <pod spec profile lines> -> the profile the (first) container gets: container level wins over pod level
_effective() {
  local pod c
  pod="$(grep '^pod:' <<<"$1" | head -1)"; pod="${pod#pod:}"
  c="$(grep '^c:' <<<"$1" | head -1)"; c="${c#c:}"
  if [[ -n "$c" && "$c" != "/" ]]; then echo "$c"; else echo "$pod"; fi
}

_mkdir_blocked() {
  local out
  out="$(kc -n "$NS" exec "$POD" -- sh -c 'mkdir /tmp/cka-seccomp-probe 2>&1 && rmdir /tmp/cka-seccomp-probe' 2>&1)"
  [[ "$out" == *"Operation not permitted"* ]]
}

lab_check() {
  local w eff pods p mode modes=""; w="$(worker_node 1)"
  check_gate "Pod $POD exists" exists -n "$NS" pod "$POD"
  check "$SECCOMP_DIR/profiles/$PROFILE.json exists on $w" node_exec "$w" "cmp -s /root/profiles/$PROFILE.json $SECCOMP_DIR/profiles/$PROFILE.json"
  eff="$(_effective "$(_pod_profile .spec pod "$POD")")"
  check_eq "Pod $POD uses the Localhost profile profiles/$PROFILE.json" "$eff" "Localhost/profiles/$PROFILE.json"
  check_eq "Pod $POD is Running" "$(jp -n "$NS" pod "$POD" '{.status.phase}')" "Running"
  check "mkdir in Pod $POD fails with 'Operation not permitted'" _mkdir_blocked

  eff="$(_effective "$(_pod_profile .spec.template.spec deploy legacy-api)")"
  check_eq "Deployment legacy-api uses the RuntimeDefault profile" "$eff" "RuntimeDefault/"
  check "Deployment legacy-api has no Unconfined profile left" \
    test -z "$(_pod_profile .spec.template.spec deploy legacy-api | grep Unconfined)"
  # Running Pods that are not being replaced (old ones take a while to terminate)
  pods="$(kc -n "$NS" get pod -l app=legacy-api --field-selector=status.phase=Running \
    -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{.metadata.name}} {{end}}{{end}}' 2>/dev/null)"
  for p in $pods; do
    mode="$(kc -n "$NS" exec "$p" -- sh -c "sed -n 's/^Seccomp:[[:space:]]*//p' /proc/1/status" 2>/dev/null)"
    [[ "$mode" == 2 ]] || modes+="$p:${mode:-?} "
  done
  check_eq "Running legacy-api Pods are seccomp-filtered (Seccomp: 2 in /proc/1/status)" "${pods:+${modes:-all 2}}" "all 2"
}

lab_cleanup() {
  node_exec "$(worker_node 1)" "rm -rf /root/profiles $SECCOMP_DIR/profiles/{deny,no,block}-mkdir.json" || true
}
