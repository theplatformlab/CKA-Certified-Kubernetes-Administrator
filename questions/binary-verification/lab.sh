# shellcheck shell=bash
# Copies of the release binaries on the control plane, some of them tampered
# with (bytes appended: still runnable, different checksum). Find and delete
# them. Sourced by scripts/lab.sh.
LAB_CLUSTER=cks
DIR=/opt/k8s-binaries
SUMS=/root/release.sha512
BINARIES="kube-apiserver kube-scheduler kubelet kubectl"

lab_params() {
  echo "TAMPERED=$(pick kubelet kube-apiserver kubectl kube-scheduler "kube-apiserver kubectl" "kubelet kube-scheduler")"
}

lab_setup() {
  local cp; cp="$(control_plane_node)"
  rm -f "$WORKDIR/tampered.txt"
  # The control plane binaries come from the running static Pods' images,
  # kubelet and kubectl from the node: all of them are the release builds.
  node_exec "$cp" "
    set -e
    rm -rf $DIR && mkdir -p $DIR
    for b in kube-apiserver kube-scheduler; do
      id=\$(crictl ps -q --name \"^\$b\\\$\" | head -1)
      pid=\$(crictl inspect -o go-template --template '{{.info.pid}}' \$id)
      cp /proc/\$pid/root/usr/local/bin/\$b $DIR/
    done
    cp /usr/bin/kubelet /usr/bin/kubectl $DIR/
    cd $DIR && sha512sum $BINARIES > $SUMS
    for b in $TAMPERED; do printf '\\n# patched %s\\n' \$RANDOM >> $DIR/\$b; done
    chmod 755 $DIR/*
  "
}

lab_check() {
  local cp b answer want; cp="$(control_plane_node)"
  answer="$(grep -v '^[[:space:]]*$' "$WORKDIR/tampered.txt" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s|.*/||' | sort | tr '\n' ' ')"
  want="$(tr ' ' '\n' <<<"$TAMPERED" | sort | tr '\n' ' ')"
  check_gate "tampered.txt exists" test -n "$answer"
  # check, not check_eq: a failed check must not print the answer
  check "tampered.txt lists exactly the binaries that don't match" test "$answer" = "$want"
  for b in $BINARIES; do
    if [[ " $TAMPERED " == *" $b "* ]]; then
      check "Tampered $DIR/$b is deleted" node_exec "$cp" "test ! -e $DIR/$b"
    else
      check "Genuine $DIR/$b is kept" node_exec "$cp" "cd $DIR && grep ' $b\$' $SUMS | sha512sum -c --status"
    fi
  done
}

lab_cleanup() {
  node_exec "$(control_plane_node)" "rm -rf $DIR $SUMS" || true
  rm -f "$WORKDIR/tampered.txt"
}
