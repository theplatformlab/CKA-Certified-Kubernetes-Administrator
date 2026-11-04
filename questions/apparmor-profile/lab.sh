# shellcheck shell=bash
# Load an AppArmor profile on the worker and apply it to a Pod. kind nodes
# share the host kernel, so this only works if the host has the AppArmor LSM
# active (WSL2 doesn't by default: docs/cks-wsl.md). Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
NS=doc-render
PROFILE_DIR=/root/apparmor

lab_params() {
  echo "PROFILE=$(pick k8s-deny-write deny-all-writes readonly-fs)"
  echo "POD=$(pick renderer pdf-worker thumbnailer)"
}

# _apparmor_ready <node> -> true if the kernel's AppArmor LSM is usable from the
# node. kind nodes don't always have securityfs mounted; if it has to be
# mounted, containerd and the kubelet are restarted so they notice AppArmor.
_apparmor_ready() {
  node_exec "$1" "
    [ \"\$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)\" = Y ] || exit 1
    if [ ! -d /sys/kernel/security/apparmor ]; then
      mount -t securityfs securityfs /sys/kernel/security 2>/dev/null || exit 1
      [ -d /sys/kernel/security/apparmor ] || exit 1
      systemctl restart containerd kubelet
    fi
    command -v apparmor_parser >/dev/null
  " 2>/dev/null
}

lab_setup() {
  local w; w="$(worker_node 1)"
  if ! _apparmor_ready "$w"; then
    log_error "AppArmor is not active in the kernel of this host, so profiles can't be loaded on the kind nodes."
    echo "  The kind nodes share your kernel. WSL2's kernel has AppArmor built in but not enabled;" >&2
    echo "  docs/cks-wsl.md (section AppArmor) shows how to turn it on. Other Linux hosts need AppArmor" >&2
    echo "  enabled too (Ubuntu and Debian have it by default; SELinux distributions like Fedora don't)." >&2
    return 1
  fi
  node_exec_stdin "$w" "mkdir -p $PROFILE_DIR && cat > $PROFILE_DIR/$PROFILE" <<EOF2
#include <tunables/global>

profile $PROFILE flags=(attach_disconnected) {
  #include <abstractions/base>

  file,

  # Deny all file writes.
  deny /** w,
}
EOF2
  ensure_ns "$NS"
}

# _pod_profile -> "<type>/<localhostProfile>" of the Pod's container (container level wins over Pod level)
_pod_profile() {
  local c p
  c="$(jp -n "$NS" pod "$POD" '{.spec.containers[0].securityContext.appArmorProfile.type}/{.spec.containers[0].securityContext.appArmorProfile.localhostProfile}')"
  p="$(jp -n "$NS" pod "$POD" '{.spec.securityContext.appArmorProfile.type}/{.spec.securityContext.appArmorProfile.localhostProfile}')"
  if [[ -n "$c" && "$c" != / ]]; then echo "$c"; else echo "$p"; fi
}

_confined() {
  kc -n "$NS" exec "$POD" -- sh -c 'cat /proc/1/attr/apparmor/current 2>/dev/null || cat /proc/1/attr/current' 2>/dev/null |
    grep -qF "$PROFILE (enforce)"
}

_write_denied() {
  local out
  out="$(kc -n "$NS" exec "$POD" -- sh -c 'touch /tmp/cka-apparmor-probe 2>&1 && rm -f /tmp/cka-apparmor-probe' 2>&1)"
  [[ "$out" == *"Permission denied"* ]]
}

lab_check() {
  local w; w="$(worker_node 1)"
  check_gate "Pod $POD exists" exists -n "$NS" pod "$POD"
  check "Profile $PROFILE is loaded in enforce mode on $w" \
    node_exec "$w" "grep -qxF '$PROFILE (enforce)' /sys/kernel/security/apparmor/profiles"
  check_eq "Pod $POD uses the Localhost AppArmor profile $PROFILE" "$(_pod_profile)" "Localhost/$PROFILE"
  check_eq "Pod $POD runs on $w" "$(jp -n "$NS" pod "$POD" '{.spec.nodeName}')" "$w"
  check_eq "Pod $POD is Running" "$(jp -n "$NS" pod "$POD" '{.status.phase}')" "Running"
  check "The container runs confined by $PROFILE" _confined
  check "Writing a file in the container is denied" _write_denied
}

lab_cleanup() {
  local w; w="$(worker_node 1)"
  kc -n "$NS" delete pod "$POD" --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
  node_exec "$w" "
    if [ -f $PROFILE_DIR/$PROFILE ] && [ -d /sys/kernel/security/apparmor ]; then
      apparmor_parser -R $PROFILE_DIR/$PROFILE >/dev/null 2>&1
    fi
    rm -rf $PROFILE_DIR
  " || true
}
