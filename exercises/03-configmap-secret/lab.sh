# shellcheck shell=bash
# Exercise 03 — ConfigMap and Secret. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS="${ITEM_NS:-exercise-03}"

lab_setup() {
  kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -
}

_b64d() { base64 -d 2>/dev/null; }

lab_check() {
  check_eq "ConfigMap app-config: APP_MODE=production, LOG_LEVEL=debug" \
    "$(jp -n $NS cm app-config '{.data.APP_MODE},{.data.LOG_LEVEL}')" "production,debug"
  check_eq "Secret db-creds is of type Opaque (generic)" "$(jp -n $NS secret db-creds '{.type}')" "Opaque"
  check_eq "Secret db-creds: DB_USER=admin" "$(jp -n $NS secret db-creds '{.data.DB_USER}' | _b64d)" "admin"
  check_eq "Secret db-creds: DB_PASS=s3cretP@ss" "$(jp -n $NS secret db-creds '{.data.DB_PASS}' | _b64d)" "s3cretP@ss"

  check_eq "Pod app runs busybox:1.36" "$(jp -n $NS pod app '{.spec.containers[0].image}')" "busybox:1.36"
  check_eq "Pod app is Running and Ready" \
    "$(jp -n $NS pod app '{.status.phase}/{.status.conditions[?(@.type=="Ready")].status}')" "Running/True"
  check_contains "Pod app takes env from ConfigMap app-config" \
    "$(jp -n $NS pod app '{.spec.containers[0].envFrom[*].configMapRef.name} {.spec.containers[0].env[*].valueFrom.configMapKeyRef.name}')" \
    "app-config"
  check_contains "Pod app takes env from Secret db-creds" \
    "$(jp -n $NS pod app '{.spec.containers[0].envFrom[*].secretRef.name} {.spec.containers[0].env[*].valueFrom.secretKeyRef.name}')" \
    "db-creds"

  local env
  env="$(kc -n $NS exec app -- env 2>/dev/null | grep -E '^(APP_MODE|LOG_LEVEL|DB_USER|DB_PASS)=' | sort | tr '\n' ' ')"
  check_eq "Env vars are set in the container" "$env" \
    "APP_MODE=production DB_PASS=s3cretP@ss DB_USER=admin LOG_LEVEL=debug "
  check_eq "ConfigMap app-config is mounted as a volume" \
    "$(jp -n $NS pod app '{.spec.volumes[*].configMap.name}')" "app-config"
  check_eq "/etc/config/APP_MODE contains 'production'" \
    "$(kc -n $NS exec app -- cat /etc/config/APP_MODE 2>/dev/null)" "production"
  check_eq "/etc/config/LOG_LEVEL contains 'debug'" \
    "$(kc -n $NS exec app -- cat /etc/config/LOG_LEVEL 2>/dev/null)" "debug"
}

lab_cleanup() {
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
