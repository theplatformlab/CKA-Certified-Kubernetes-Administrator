# shellcheck shell=bash
# A package with a listening service is installed on the worker; find it by
# its port, stop it for good and remove the package. Sourced by scripts/lab.sh.
LAB_CLUSTER=cks

lab_params() {
  local pkg; pkg="$(pick vsftpd rpcbind lighttpd)"
  echo "PKG=$pkg"
  case "$pkg" in
    vsftpd) echo "PORT=21" ;;
    rpcbind) echo "PORT=111" ;;
    lighttpd) echo "PORT=80" ;;
  esac
}

# _units -> the systemd units the package brings (rpcbind is socket-activated)
_units() { if [[ "$PKG" == rpcbind ]]; then echo "rpcbind.service rpcbind.socket"; else echo "$PKG.service"; fi; }

lab_setup() {
  local w; w="$(worker_node 1)"
  rm -f "$WORKDIR/package.txt"
  # kind's policy-rc.d keeps apt from starting and stopping services; a real
  # node has none (init-cluster.sh removes it too, this covers older clusters).
  if ! node_exec "$w" "
    export DEBIAN_FRONTEND=noninteractive
    rm -f /usr/sbin/policy-rc.d
    dpkg -s $PKG >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq $PKG >/dev/null; }
    systemctl enable --now $(_units) >/dev/null 2>&1
    for i in \$(seq 20); do ss -Hltn 'sport = :$PORT' | grep -q . && exit 0; sleep 0.5; done
    exit 1
  "; then
    log_error "Could not install and start $PKG on $w (no internet access?)"
    return 1
  fi
}

_listening() { node_exec "$(worker_node 1)" "ss -Hltn 'sport = :$PORT' | grep -q ."; }

_installed() { node_exec "$(worker_node 1)" "dpkg-query -W -f='\${Status}' $PKG 2>/dev/null | grep -q 'install ok installed'"; }

# _enabled -> true if one of the package's units is still enabled (missing unit files count as disabled)
_enabled() {
  local u
  for u in $(_units); do
    [[ "$(node_exec "$(worker_node 1)" "systemctl is-enabled $u 2>/dev/null")" == enabled ]] && return 0
  done
  return 1
}

lab_check() {
  local w; w="$(worker_node 1)"
  check_gate "Nothing listens on TCP port $PORT on $w" _not_listening
  check "package.txt names the package that provided the service" \
    test "$(cat "$WORKDIR/package.txt" 2>/dev/null | tr -d '[:space:]')" = "$PKG"
  check_not "The package is removed" _installed
  check_not "None of its systemd units is enabled any more" _enabled
  check_eq "kubelet on $w is still active" "$(node_exec "$w" "systemctl is-active kubelet" 2>/dev/null)" "active"
  check_eq "Node $w is Ready" "$(jp node "$w" '{.status.conditions[?(@.type=="Ready")].status}')" "True"
}

_not_listening() { ! _listening; }

lab_cleanup() {
  node_exec "$(worker_node 1)" "
    systemctl disable --now $(_units) >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq $PKG >/dev/null 2>&1
    true
  " || true
  rm -f "$WORKDIR/package.txt"
}
