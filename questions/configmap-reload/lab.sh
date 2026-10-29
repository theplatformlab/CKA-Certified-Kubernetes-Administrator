# shellcheck shell=bash
# ConfigMap changes and running pods. Sourced by scripts/lab.sh.
LAB_CLUSTER=practice
NS=config-demo

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: $NS
data:
  mode: development
  message: v1
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: config-app
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: config-app
  template:
    metadata:
      labels:
        app: config-app
    spec:
      containers:
      - name: app
        image: busybox:1.37
        command: ["sh", "-c", "while true; do echo \"\$APP_MODE \$(cat /etc/app/message)\"; sleep 10; done"]
        env:
        - name: APP_MODE
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: mode
        volumeMounts:
        - name: config
          mountPath: /etc/app
      volumes:
      - name: config
        configMap:
          name: app-config
EOF
}

lab_check() {
  check_gate "ConfigMap app-config has mode=production" test "$(jp -n $NS cm app-config '{.data.mode}')" = "production"
  check_eq "ConfigMap app-config has message=v2" "$(jp -n $NS cm app-config '{.data.message}')" "v2"
  check_eq "Deployment config-app: 2/2 replicas updated and ready" \
    "$(jp -n $NS deploy config-app '{.status.updatedReplicas}/{.status.readyReplicas}')" "2/2"
  local pods p env_ok=true file_ok=true
  # Running pods that are not terminating (old pods linger during a rollout).
  pods="$(kc -n $NS get pods -l app=config-app -o json 2>/dev/null \
    | jq -r '.items[] | select(.metadata.deletionTimestamp == null and .status.phase == "Running") | .metadata.name')"
  [[ -z "$pods" ]] && { env_ok=false; file_ok=false; }
  for p in $pods; do
    [[ "$(kc -n $NS exec "$p" -- printenv APP_MODE 2>/dev/null)" == production ]] || env_ok=false
    [[ "$(kc -n $NS exec "$p" -- cat /etc/app/message 2>/dev/null)" == v2 ]] || file_ok=false
  done
  check "All pods have APP_MODE=production" $env_ok
  check "All pods see message v2 in /etc/app/message" $file_ok
}
