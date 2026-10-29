# shellcheck shell=bash
# Exercise 05 — NetworkPolicy. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-05}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

# _reach <labels> <ip>  — prints OPEN or BLOCKED for HTTP to <ip>:80 from a probe pod.
_reach() {
  [[ -n "$2" ]] || { echo "no-pod-ip"; return; }
  probe $NS "$1" "if wget -qO- -T 3 http://$2 >/dev/null 2>&1; then echo OPEN; else echo BLOCKED; fi" | tr -d '[:space:]'
}

lab_check() {
  local p
  for p in frontend backend attacker; do
    check_eq "Pod $p (nginx:1.27, role=$p) is Running" \
      "$(jp -n $NS pod $p '{.spec.containers[0].image} {.metadata.labels.role} {.status.phase}')" "nginx:1.27 $p Running"
  done

  check_eq "NetworkPolicy backend-policy selects role=backend" \
    "$(jp -n $NS netpol backend-policy '{.spec.podSelector.matchLabels.role}')" "backend"
  check_eq "backend-policy has policyTypes Ingress and Egress" \
    "$(jp -n $NS netpol backend-policy '{.spec.policyTypes[*]}' | tr ' ' '\n' | sort | xargs)" "Egress Ingress"
  check_eq "Ingress allows only role=frontend on TCP port 80" \
    "$(jp -n $NS netpol backend-policy '{.spec.ingress[*].from[*].podSelector.matchLabels.role} {.spec.ingress[*].ports[*].protocol}/{.spec.ingress[*].ports[*].port}')" \
    "frontend TCP/80"
  check_contains "Egress allows UDP port 53 (DNS)" \
    "$(jp -n $NS netpol backend-policy '{range .spec.egress[*].ports[*]}{.protocol}/{.port} {end}')" "UDP/53"

  local ip fip
  ip="$(jp -n $NS pod backend '{.status.podIP}')"
  fip="$(jp -n $NS pod frontend '{.status.podIP}')"
  check_eq "role=frontend can reach backend:80" "$(_reach role=frontend "$ip")" "OPEN"
  check_eq "role=attacker cannot reach backend:80" "$(_reach role=attacker "$ip")" "BLOCKED"
  check_eq "backend can still resolve DNS names (DNS egress allowed)" \
    "$(kc -n $NS exec backend -- sh -c 'getent hosts kubernetes.default.svc.cluster.local >/dev/null && echo OK' 2>/dev/null)" "OK"
  check_eq "backend cannot open other egress connections (frontend:80 blocked)" \
    "$( [[ -n "$fip" ]] && kc -n $NS exec backend -- sh -c "curl -s -m 3 -o /dev/null http://$fip && echo OPEN || echo BLOCKED" 2>/dev/null)" "BLOCKED"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
