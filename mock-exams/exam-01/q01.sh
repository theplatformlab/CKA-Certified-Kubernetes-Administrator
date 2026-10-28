# shellcheck shell=bash
# Q1 — Fix a crashing pod with a ConfigMap
Q_CLUSTER=practice
NS=production
CONTENT='database_host: postgres.production.svc.cluster.local'

q_setup() {
  ensure_ns "$NS"
  mkdir -p "$CKA_EXAM_HOME/q01"
  cat >"$CKA_EXAM_HOME/q01/app-frontend.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: app-frontend
  namespace: production
  labels:
    app: frontend
spec:
  containers:
  - name: app
    image: busybox:1.37
    command:
    - sh
    - -c
    - |
      if [ ! -f /etc/app/config.yaml ]; then
        echo "FATAL: /etc/app/config.yaml not found" >&2
        exit 1
      fi
      cat /etc/app/config.yaml
      exec sleep 86400
EOF
  kc apply -f "$CKA_EXAM_HOME/q01/app-frontend.yaml"
}

q_check() {
  check_gate "ConfigMap app-config exists" exists -n $NS cm app-config
  check_eq "ConfigMap app-config has key config.yaml with the database_host line" \
    "$(jp -n $NS cm app-config '{.data.config\.yaml}' | sed -e 's/[[:space:]]*$//')" "$CONTENT"
  check_contains "Pod app-frontend uses ConfigMap app-config as a volume" \
    "$(jp -n $NS pod app-frontend '{.spec.volumes[*].configMap.name}')" "app-config"
  check_eq "Pod app-frontend still runs busybox:1.37" \
    "$(jp -n $NS pod app-frontend '{.spec.containers[0].image}')" "busybox:1.37"
  check_eq "Pod app-frontend is Ready" \
    "$(jp -n $NS pod app-frontend '{.status.conditions[?(@.type=="Ready")].status}')" "True"
  check_eq "/etc/app/config.yaml in the pod has the expected content" \
    "$(kc -n $NS exec app-frontend -- cat /etc/app/config.yaml 2>/dev/null | sed -e 's/[[:space:]]*$//')" "$CONTENT"
}
