# shellcheck shell=bash
# Five Pods with old and current images; delete those whose image has CRITICAL
# vulnerabilities. Setup scans the images once with the trivy on the control
# plane and stores the result there, so the check never runs trivy.
# Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
NS=media-portal
STATE=/var/lib/cka-lab/image-scan
PODS=(portal gateway sessions queue metrics)
IMAGES=(nginx:1.19-alpine httpd:2.4.39-alpine redis:7.4-alpine memcached:1.6-alpine python:3.9-alpine3.18)

lab_params() {
  echo "ROTATE=$(rand_int 0 4)"
}

# _image <pod index> -> its image (the assignment rotates per session)
_image() { echo "${IMAGES[$(( ($1 + ROTATE) % ${#IMAGES[@]} ))]}"; }

lab_setup() {
  local cp i img; cp="$(control_plane_node)"
  ensure_ns "$NS"
  for i in "${!PODS[@]}"; do
    img="$(_image "$i")"
    if [[ "$img" == python:* ]]; then
      kc -n "$NS" run "${PODS[$i]}" --image="$img" --labels=app="${PODS[$i]}" --command -- sleep 1d >/dev/null 2>&1 || true
    else
      kc -n "$NS" run "${PODS[$i]}" --image="$img" --labels=app="${PODS[$i]}" >/dev/null 2>&1 || true
    fi
  done
  log_info "Scanning the images with trivy on $cp (expected result for grading) ..."
  node_exec "$cp" "rm -rf $STATE && mkdir -p $STATE"
  for i in "${!PODS[@]}"; do
    img="$(_image "$i")"
    # trivy exits 1 with --exit-code 1 if it finds anything of the given severity
    if ! node_exec "$cp" "trivy image -q --scanners vuln --severity CRITICAL --exit-code 1 $img >/dev/null 2>&1; echo \$? > $STATE/${PODS[$i]}; [ \"\$(cat $STATE/${PODS[$i]})\" -le 1 ]"; then
      log_error "trivy could not scan $img (no internet access?)"
      return 1
    fi
  done
  node_exec "$cp" "grep -l 1 $STATE/* >/dev/null" || log_warn "No image has CRITICAL vulnerabilities today: nothing to delete"
  kc -n "$NS" wait --for=condition=Ready pod --all --timeout=180s >/dev/null || true
}

lab_check() {
  local cp i pod verdict want state deleted=0; cp="$(control_plane_node)"
  for pod in "${PODS[@]}"; do
    [[ "$(jp -n "$NS" pod "$pod" '{.metadata.uid}{.metadata.deletionTimestamp}')" =~ ^[0-9a-f-]+$ ]] || deleted=$(( deleted + 1 ))
  done
  check_gate "At least one Pod in $NS was deleted" test "$deleted" -gt 0
  for i in "${!PODS[@]}"; do
    pod="${PODS[$i]}"
    verdict="$(node_exec "$cp" "cat $STATE/$pod" 2>/dev/null)"
    [[ "$verdict" == 1 ]] && want=deleted || want=Running
    # A Pod that is terminating counts as deleted.
    state="$(jp -n "$NS" pod "$pod" '{.status.phase}{.metadata.deletionTimestamp}')"
    [[ "$state" == Running ]] || state=""
    # check, not check_eq: a failed check must not print the answer
    check "Pod $pod ($(_image "$i")) is deleted if its image has CRITICAL vulnerabilities, else running" test "${state:-deleted}" = "$want"
  done
}

lab_cleanup() {
  node_exec "$(control_plane_node)" "rm -rf $STATE" || true
}
