# shellcheck shell=bash
# Q1 — Service discovery and DNS
Q_CLUSTER=practice

q_setup() {
  ensure_ns frontend
  ensure_ns backend
  mkdir -p "$CKA_EXAM_HOME/q01"
  kc -n frontend create deployment web-ui --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
  kc -n frontend create service clusterip web-ui --tcp=3000:80 --dry-run=client -o yaml | kc apply -f -
}

q_check() {
  local dir="$CKA_EXAM_HOME/q01"
  check_gate "~/cka-exam/q01/dns.txt exists" test -s "$dir/dns.txt"
  check_match "dns.txt contains the Service FQDN" \
    "$(tr -d '[:space:]' <"$dir/dns.txt" 2>/dev/null)" '^web-ui\.frontend\.svc\.cluster\.local\.?$'
  check_eq "Pod dns-test runs busybox:1.37 in namespace backend" \
    "$(jp -n backend pod dns-test '{.spec.containers[0].image} {.status.phase}')" "busybox:1.37 Running"
  local ip; ip="$(jp -n frontend svc web-ui '{.spec.clusterIP}')"
  check_contains "nslookup.txt shows the Service's ClusterIP ($ip)" "$(cat "$dir/nslookup.txt" 2>/dev/null)" "${ip:-none}"
}
