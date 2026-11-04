# shellcheck shell=bash
# PodDisruptionBudget. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=web

lab_params() {
  echo "REPLICAS=$(rand_int 6 10)"
  echo "MAX_UNAVAILABLE=$(pick 1 2 3)"
}

lab_setup() {
  ensure_ns "$NS"
  kc -n $NS create deployment frontend --image=nginx:1.28 --replicas="$REPLICAS" --dry-run=client -o yaml | kc apply -f -
}

lab_check() {
  check_gate "PDB frontend-pdb exists" exists -n $NS pdb frontend-pdb
  check_eq "maxUnavailable is $MAX_UNAVAILABLE" "$(jp -n $NS pdb frontend-pdb '{.spec.maxUnavailable}')" "$MAX_UNAVAILABLE"
  check_eq "PDB selects app=frontend" "$(jp -n $NS pdb frontend-pdb '{.spec.selector.matchLabels.app}')" "frontend"
  check_eq "PDB covers $REPLICAS pods and allows $MAX_UNAVAILABLE disruptions" \
    "$(jp -n $NS pdb frontend-pdb '{.status.expectedPods}/{.status.disruptionsAllowed}')" "$REPLICAS/$MAX_UNAVAILABLE"
}
