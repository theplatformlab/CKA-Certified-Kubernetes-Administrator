# shellcheck shell=bash
# SBOMs in SPDX and CycloneDX format with trivy, and a question answered from
# them. Setup stores the expected package version on the control plane, so the
# check doesn't run trivy. Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
STATE=/var/lib/cka-lab/sbom

lab_params() {
  echo "IMAGE=$(pick redis:7.4-alpine memcached:1.6-alpine)"
  echo "PKG=$(pick libcrypto3 musl zlib busybox)"
}

lab_setup() {
  local cp; cp="$(control_plane_node)"
  rm -f "$WORKDIR"/sbom.spdx.json "$WORKDIR"/sbom.cdx.json "$WORKDIR"/version.txt
  # Floating tags change, so the expected version is read from today's image.
  if ! node_exec "$cp" "
    set -e
    mkdir -p $STATE
    trivy image -q --format cyclonedx $IMAGE > $STATE/bom.json
    jq -r '.components[] | select(.name == \"$PKG\") | .version' $STATE/bom.json | head -1 > $STATE/version
    rm -f $STATE/bom.json
    test -s $STATE/version
  "; then
    log_error "trivy could not create an SBOM of $IMAGE with package $PKG (no internet access?)"
    return 1
  fi
}

# _json <file> <jq filter> -> the value, empty if the file is missing or not JSON
_json() { jq -r "$2 // empty" "$1" 2>/dev/null; }

lab_check() {
  local spdx="$WORKDIR/sbom.spdx.json" cdx="$WORKDIR/sbom.cdx.json" want
  want="$(node_exec "$(control_plane_node)" "cat $STATE/version" 2>/dev/null)"
  check_gate "sbom.spdx.json exists" test -s "$spdx"
  check_match "sbom.spdx.json is an SPDX JSON document" "$(_json "$spdx" .spdxVersion)" "^SPDX-"
  check_eq "sbom.spdx.json describes $IMAGE" "$(_json "$spdx" .name)" "$IMAGE"
  check_eq "sbom.spdx.json lists package $PKG" "$(_json "$spdx" "[.packages[]? | select(.name == \"$PKG\")] | length > 0")" "true"
  check_eq "sbom.cdx.json is a CycloneDX document" "$(_json "$cdx" .bomFormat)" "CycloneDX"
  check_eq "sbom.cdx.json describes $IMAGE" "$(_json "$cdx" .metadata.component.name)" "$IMAGE"
  # check, not check_eq: a failed check must not print the answer
  check "version.txt has the version of $PKG in $IMAGE" test "$(cat "$WORKDIR/version.txt" 2>/dev/null | tr -d '[:space:]')" = "${want:-unknown}"
}

lab_cleanup() {
  node_exec "$(control_plane_node)" "rm -rf $STATE" || true
}
