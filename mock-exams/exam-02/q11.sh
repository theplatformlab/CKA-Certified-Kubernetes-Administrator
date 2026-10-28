# shellcheck shell=bash
# Q11 — PodDisruptionBudget
Q_CLUSTER=practice
NS=web

q_setup() {
  ensure_ns "$NS"
  kc -n $NS create deployment frontend --image=nginx:1.28 --replicas=10 --dry-run=client -o yaml | kc apply -f -
}

q_check() {
  check_gate "PDB frontend-pdb exists" exists -n $NS pdb frontend-pdb
  check_eq "maxUnavailable is 2" "$(jp -n $NS pdb frontend-pdb '{.spec.maxUnavailable}')" "2"
  check_eq "PDB selects app=frontend" "$(jp -n $NS pdb frontend-pdb '{.spec.selector.matchLabels.app}')" "frontend"
  check_eq "PDB covers 10 pods and allows 2 disruptions" \
    "$(jp -n $NS pdb frontend-pdb '{.status.expectedPods}/{.status.disruptionsAllowed}')" "10/2"
}
