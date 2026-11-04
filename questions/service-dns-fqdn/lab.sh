# shellcheck shell=bash
# Service discovery and DNS. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice

lab_setup() {
  ensure_ns portal
  ensure_ns orders
  mkdir -p "$WORKDIR"
  kc -n portal create deployment web-ui --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
  kc -n portal create service clusterip web-ui --tcp=3000:80 --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  local dir="$WORKDIR"
  check_gate "dns.txt exists" test -s "$dir/dns.txt"
  check_match "dns.txt contains the Service FQDN" \
    "$(tr -d '[:space:]' 2>/dev/null <"$dir/dns.txt")" '^web-ui\.portal\.svc\.cluster\.local\.?$'
  check_eq "Pod dns-test runs busybox:1.37 in namespace orders" \
    "$(jp -n orders pod dns-test '{.spec.containers[0].image} {.status.phase}')" "busybox:1.37 Running"
  local ip; ip="$(jp -n portal svc web-ui '{.spec.clusterIP}')"
  check_contains "nslookup.txt shows the Service's ClusterIP ($ip)" "$(cat "$dir/nslookup.txt" 2>/dev/null)" "${ip:-none}"
}
