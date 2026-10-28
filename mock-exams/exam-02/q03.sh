# shellcheck shell=bash
# Q3 — Secrets as environment variables
Q_CLUSTER=practice
NS=apps

q_setup() { ensure_ns "$NS"; }

_secret() { jp -n $NS secret db-credentials "{.data.$1}" | base64 -d 2>/dev/null; }

q_check() {
  check_gate "Secret db-credentials exists" exists -n $NS secret db-credentials
  check_eq "Secret has DB_USER/DB_PASSWORD/DB_NAME" "$(_secret DB_USER)/$(_secret DB_PASSWORD)/$(_secret DB_NAME)" "dbuser/secret123/appdb"
  check_eq "Deployment db-client is Ready with busybox:1.37" \
    "$(jp -n $NS deploy db-client '{.status.readyReplicas} {.spec.template.spec.containers[0].image}')" "1 busybox:1.37"
  check_eq "Environment in the pod has the Secret values" \
    "$(kc -n $NS exec deploy/db-client -- sh -c 'echo $DB_USER/$DB_PASSWORD/$DB_NAME' 2>/dev/null)" "dbuser/secret123/appdb"
  check_contains "Values come from Secret db-credentials" \
    "$(jp -n $NS deploy db-client '{.spec.template.spec.containers[0].envFrom[*].secretRef.name} {.spec.template.spec.containers[0].env[*].valueFrom.secretKeyRef.name}')" \
    "db-credentials"
  check_not "No secret value is written into the Deployment" \
    bash -c "kubectl --context '$CTX' -n $NS get deploy db-client -o yaml | grep -q secret123"
}
