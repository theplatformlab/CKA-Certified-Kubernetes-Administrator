# shellcheck shell=bash
# Query the API with a ServiceAccount token. Sourced by scripts/lab.sh.
# ServiceAccount inventory-sync may list Secrets in keystore, but it has
# automountServiceAccountToken: false: a pod that just names it gets no token,
# the pod has to opt back in. The check reads the saved API response; a
# SecretList (not kubectl's "List") shows it came from the API itself.
LAB_CLUSTER=practice
NS=keystore
SA=inventory-sync
POD=api-client
IMAGE=curlimages/curl:8.17.0

lab_params() {
  echo "DB_PASSWORD=$(rand_suffix 16)"
}

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SA
  namespace: $NS
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-lister
  namespace: $NS
rules:
- apiGroups: [""]
  resources: [secrets]
  verbs: [list]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: inventory-sync-secret-lister
  namespace: $NS
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: secret-lister
subjects:
- kind: ServiceAccount
  name: $SA
  namespace: $NS
YAML
  kc -n "$NS" create secret generic warehouse-db --from-literal=username=inventory \
    --from-literal=password="$DB_PASSWORD" --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" create secret generic carrier-api --from-literal=api-key="ck-$(rand_suffix 20)" \
    --dry-run=client -o yaml | kc apply -f -
  kc -n "$NS" create secret generic sftp-upload --from-literal=host=sftp.example.internal \
    --from-literal=user=upload --dry-run=client -o yaml | kc apply -f -
  rm -f "$WORKDIR/secrets.json"
}

_json() { jq -r "$1" "$WORKDIR/secrets.json" 2>/dev/null; }

lab_check() {
  check_gate "Pod $POD exists in $NS" exists -n "$NS" pod "$POD"
  check_eq "Pod $POD runs as ServiceAccount $SA" "$(jp -n "$NS" pod "$POD" '{.spec.serviceAccountName}')" "$SA"
  check_eq "Pod $POD uses image $IMAGE" "$(jp -n "$NS" pod "$POD" '{.spec.containers[0].image}')" "$IMAGE"
  check_eq "Pod $POD is Running" "$(jp -n "$NS" pod "$POD" '{.status.phase}')" "Running"
  check_match "Pod $POD has the ServiceAccount token mounted" \
    "$(jp -n "$NS" pod "$POD" '{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}')" "token"
  check_eq "secrets.json is the API's SecretList response" "$(_json .kind)" "SecretList"
  check_eq "secrets.json contains every Secret of $NS" \
    "$(_json '.items[].metadata.name' | sort | paste -sd' ')" \
    "$(jp -n "$NS" secret '{.items[*].metadata.name}' | tr ' ' '\n' | sort | paste -sd' ')"
  check_eq "secrets.json has the data of Secret warehouse-db" \
    "$(_json '.items[] | select(.metadata.name == "warehouse-db") | .data.password' | base64 -d 2>/dev/null)" "$DB_PASSWORD"
}
