# shellcheck shell=bash
# Q12 — Custom resources
Q_CLUSTER=practice
NS=team-data

_crd() {
  local plural="$1" kind="$2" group="$3"
  kc apply -f - <<EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: $plural.$group
spec:
  group: $group
  scope: Namespaced
  names:
    plural: $plural
    singular: ${kind,,}
    kind: $kind
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            description: Desired state of the $kind.
            properties:
              engine:
                type: string
                description: Database engine.
                enum: [postgres, mysql]
              version:
                type: string
                description: Engine version, as a string (e.g. "17").
              storageGB:
                type: integer
                description: Size of the data volume in GB.
                minimum: 1
              schedule:
                type: string
                description: Cron schedule.
EOF
}

q_setup() {
  ensure_ns "$NS"
  mkdir -p "$CKA_EXAM_HOME/q12"
  _crd databases Database example.com
  _crd backups Backup example.com
  _crd widgets Widget acme.io
  kc wait --for=condition=Established crd/databases.example.com --timeout=60s
  kc apply -f - <<EOF
apiVersion: example.com/v1
kind: Database
metadata:
  name: legacy-db
  namespace: $NS
spec:
  engine: mysql
  version: "5.7"
  storageGB: 5
EOF
}

q_check() {
  check_gate "Database orders-db exists" exists -n $NS databases.example.com orders-db
  check_eq "orders-db: engine postgres, version \"17\", storageGB 20" \
    "$(jp -n $NS databases.example.com orders-db '{.spec.engine} {.spec.version} {.spec.storageGB}')" "postgres 17 20"
  check_not "Database legacy-db is deleted" exists -n $NS databases.example.com legacy-db
  check_eq "crds.txt lists the example.com CRDs" \
    "$(sort -u "$CKA_EXAM_HOME/q12/crds.txt" 2>/dev/null | tr -d ' ' | grep -v '^$' | tr '\n' ' ')" \
    "backups.example.com databases.example.com "
}
