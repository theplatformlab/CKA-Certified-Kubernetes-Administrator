# shellcheck shell=bash
# Least privilege for a ServiceAccount. Sourced by scripts/lab.sh.
# deploy-bot is cluster-wide "*/*/*" through a ClusterRoleBinding and admin in
# a second namespace through a RoleBinding that is easy to miss. It needs to
# roll out Deployments in shipyard and read their pods and logs, nothing more.
LAB_CLUSTER=practice
NS=shipyard
NS2=shipyard-legacy
SA=deploy-bot
WIDE=deploy-bot-all

lab_setup() {
  kc wait --for=delete "namespace/$NS2" --timeout=180s >/dev/null 2>&1 || true
  ensure_ns "$NS"
  ensure_ns "$NS2"
  kc apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA
  namespace: $NS
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $WIDE
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $WIDE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: $WIDE
subjects:
- kind: ServiceAccount
  name: $SA
  namespace: $NS
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: legacy-ci
  namespace: $NS2
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
- kind: ServiceAccount
  name: $SA
  namespace: $NS
YAML
  kc -n "$NS" create deployment web --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS2" create deployment old-web --image=nginx:1.28 --dry-run=client -o yaml | kc apply -f -
  rm -f "$WORKDIR/deploy-bot-permissions.txt"
}

_as="system:serviceaccount:$NS:$SA"
_can() { kc auth can-i "$@" --as "$_as" >/dev/null 2>&1; }
# _can_all <resource> <namespace> <verb>...
_can_all() { local r="$1" n="$2" v; shift 2; for v; do _can "$v" "$r" -n "$n" || return 1; done; }
_can_any() { local r="$1" n="$2" v; shift 2; for v; do _can "$v" "$r" -n "$n" && return 0; done; return 1; }
_pod_writes() { _can_any pods "$NS" create delete || _can create pods --subresource=exec -n "$NS"; }
_cluster_access() { _can list nodes || _can list namespaces || _can list pods -n kube-system; }

lab_check() {
  local f="$WORKDIR/deploy-bot-permissions.txt" refs
  check_gate "Role deploy-bot exists in $NS" exists -n "$NS" role deploy-bot
  check_eq "RoleBinding deploy-bot binds Role deploy-bot to ServiceAccount $SA" \
    "$(jp -n "$NS" rolebinding deploy-bot '{.roleRef.kind}/{.roleRef.name} {.subjects[*].kind}/{.subjects[*].namespace}/{.subjects[*].name}')" \
    "Role/deploy-bot ServiceAccount/$NS/$SA"
  check "deploy-bot can get, list, watch, update and patch Deployments in $NS" _can_all deployments.apps "$NS" get list watch update patch
  check "deploy-bot can get, list and watch Pods in $NS" _can_all pods "$NS" get list watch
  check "deploy-bot can read Pod logs in $NS" _can get pods --subresource=log -n "$NS"
  check_not "deploy-bot cannot create or delete Deployments in $NS" _can_any deployments.apps "$NS" create delete deletecollection
  check_not "deploy-bot cannot create, delete or exec into Pods in $NS" _pod_writes
  check_not "deploy-bot cannot read Secrets in $NS" _can_any secrets "$NS" get list
  check_not "deploy-bot has no access in $NS2" _can_any deployments.apps "$NS2" get list
  check_not "deploy-bot has no cluster-wide access (nodes, namespaces, kube-system)" _cluster_access
  check_not "ClusterRoleBinding $WIDE is deleted" exists clusterrolebinding "$WIDE"
  check_not "ClusterRole $WIDE is deleted" exists clusterrole "$WIDE"
  refs="$(kc get rolebindings -A -o json 2>/dev/null | jq -r --arg ns "$NS" --arg sa "$SA" \
    '.items[] | select(.metadata.namespace != $ns) | select(any(.subjects[]?; .kind == "ServiceAccount" and .name == $sa and .namespace == $ns)) | .metadata.namespace + "/" + .metadata.name')"
  check_eq "No RoleBinding outside $NS grants deploy-bot anything" "$refs" ""
  check_eq "Role deploy-bot uses no wildcards" \
    "$(kc -n "$NS" get role deploy-bot -o json 2>/dev/null | jq '[.rules[] | (.apiGroups // []) + (.resources // []) + (.verbs // []) | .[] | select(. == "*")] | length')" "0"
  check_match "deploy-bot-permissions.txt lists deployments.apps" "$(grep -E '^deployments\.apps ' "$f" 2>/dev/null)" 'update.*patch|patch.*update'
  check_not "deploy-bot-permissions.txt shows no wildcard rule (*.*)" grep -qE '^\*\.\*' "$f"
}

lab_cleanup() {
  kc delete clusterrolebinding "$WIDE" --ignore-not-found >/dev/null
  kc delete clusterrole "$WIDE" --ignore-not-found >/dev/null
  kc delete namespace "$NS" "$NS2" --ignore-not-found --wait=false
}
