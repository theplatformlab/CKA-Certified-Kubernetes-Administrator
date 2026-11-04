# shellcheck shell=bash
# Harden the ServiceAccounts of a namespace. Sourced by scripts/lab.sh.
# Both Deployments run as the default ServiceAccount, which a forgotten
# ClusterRoleBinding makes cluster-admin. Only crm-api talks to the API (it
# reads ConfigMaps); crm-frontend needs no token at all.
LAB_CLUSTER=practice
NS=crm-portal
CRB=crm-portal-default-admin

lab_setup() {
  ensure_ns "$NS"
  kc apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $CRB
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: default
  namespace: $NS
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: crm-settings
  namespace: $NS
data:
  region: eu-central
  feature.leads: "true"
---
apiVersion: v1
kind: Secret
metadata:
  name: crm-db
  namespace: $NS
stringData:
  password: $(rand_suffix 16)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crm-api
  namespace: $NS
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crm-api
  template:
    metadata:
      labels:
        app: crm-api
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: api
        image: curlimages/curl:8.17.0
        command:
        - sh
        - -c
        - |
          SA=/var/run/secrets/kubernetes.io/serviceaccount
          while true; do
            curl -s -o /dev/null -w "configmaps: %{http_code}\n" --cacert \$SA/ca.crt \
              -H "Authorization: Bearer \$(cat \$SA/token)" \
              https://kubernetes.default.svc/api/v1/namespaces/$NS/configmaps
            sleep 30
          done
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crm-frontend
  namespace: $NS
spec:
  replicas: 2
  selector:
    matchLabels:
      app: crm-frontend
  template:
    metadata:
      labels:
        app: crm-frontend
    spec:
      terminationGracePeriodSeconds: 1
      containers:
      - name: web
        image: nginx:1.28
YAML
  kc -n "$NS" rollout status deploy crm-api --timeout=120s
  kc -n "$NS" rollout status deploy crm-frontend --timeout=120s
}

_can() { kc auth can-i "$@" >/dev/null 2>&1; }
# _can_all|_can_any <user> <verb>... — every / at least one verb allowed on configmaps in \$NS
_can_all() { local u="$1" v; shift; for v; do _can "$v" configmaps -n "$NS" --as "$u" || return 1; done; }
_can_any() { local u="$1" v; shift; for v; do _can "$v" configmaps -n "$NS" --as "$u" && return 0; done; return 1; }

# _pods <app> <jsonpath per pod> — one line per running (not terminating) pod of the app
_pods() {
  kc -n "$NS" get pods -l "app=$1" -o jsonpath="{range .items[?(@.status.phase==\"Running\")]}{.metadata.deletionTimestamp}|$2{\"\n\"}{end}" 2>/dev/null \
    | grep -v '^[^|]' | cut -d'|' -f2-
}

lab_check() {
  local sa="system:serviceaccount:$NS:crm-api" def="system:serviceaccount:$NS:default" tok lines
  check_gate "ServiceAccount crm-api exists in $NS" exists -n "$NS" serviceaccount crm-api
  check_eq "ServiceAccount default does not automount tokens" \
    "$(jp -n "$NS" serviceaccount default '{.automountServiceAccountToken}')" "false"
  check "crm-api can get, list and watch ConfigMaps in $NS" _can_all "$sa" get list watch
  check_not "crm-api cannot change ConfigMaps in $NS" _can_any "$sa" create update patch delete
  check_not "crm-api cannot read Secrets in $NS" _can get secrets -n "$NS" --as "$sa"
  check_not "crm-api cannot list ConfigMaps in other namespaces" _can list configmaps -n kube-system --as "$sa"
  check_not "ClusterRoleBinding $CRB is gone" exists clusterrolebinding "$CRB"
  check_not "ServiceAccount default of $NS is no longer cluster-admin" _can list secrets -n kube-system --as "$def"
  check_eq "Deployment crm-api runs as ServiceAccount crm-api" \
    "$(jp -n "$NS" deploy crm-api '{.spec.template.spec.serviceAccountName}')" "crm-api"
  check_eq "Deployment crm-api is rolled out and ready" \
    "$(jp -n "$NS" deploy crm-api '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "1/1/1"
  tok='{.spec.serviceAccountName}:{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}'
  lines="$(_pods crm-api "$tok" | sort -u)"
  check_eq "Running crm-api pods use ServiceAccount crm-api with a mounted token" "$lines" "crm-api:token"
  lines="$(_pods crm-frontend '{.metadata.name}:{.spec.volumes[*].projected.sources[*].serviceAccountToken.path}')"
  check_eq "Running crm-frontend pods have no ServiceAccount token mounted" \
    "$(grep -c . <<<"$lines") running, with token: $(grep -c token <<<"$lines")" "2 running, with token: 0"
  check_eq "Deployment crm-frontend is rolled out and ready" \
    "$(jp -n "$NS" deploy crm-frontend '{.status.updatedReplicas}/{.status.readyReplicas}/{.spec.replicas}')" "2/2/2"
}

lab_cleanup() {
  kc delete clusterrolebinding "$CRB" --ignore-not-found >/dev/null
  kc delete namespace "$NS" --ignore-not-found --wait=false
}
