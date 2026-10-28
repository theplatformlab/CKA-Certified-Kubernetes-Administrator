# shellcheck shell=bash
# Q12 — StatefulSet with stable storage
Q_CLUSTER=practice
NS=databases

q_setup() { ensure_ns "$NS"; }

q_check() {
  check_eq "Service database-cluster is headless" "$(jp -n $NS svc database-cluster '{.spec.clusterIP}')" "None"
  check_eq "Service exposes port 5432 named postgres, selector app=database-cluster" \
    "$(jp -n $NS svc database-cluster '{.spec.ports[0].name}:{.spec.ports[0].port} {.spec.selector.app}')" \
    "postgres:5432 database-cluster"
  check_eq "StatefulSet uses serviceName database-cluster and 3 replicas" \
    "$(jp -n $NS sts database-cluster '{.spec.serviceName} {.spec.replicas}')" "database-cluster 3"
  check_eq "Container postgres runs postgres:17-alpine" \
    "$(jp -n $NS sts database-cluster '{.spec.template.spec.containers[?(@.name=="postgres")].image}')" "postgres:17-alpine"
  check_eq "PGDATA is /var/lib/postgresql/data/pgdata" \
    "$(jp -n $NS sts database-cluster '{.spec.template.spec.containers[0].env[?(@.name=="PGDATA")].value}')" \
    "/var/lib/postgresql/data/pgdata"
  check_eq "Volume claim template data: 1Gi ReadWriteOnce" \
    "$(jp -n $NS sts database-cluster '{.spec.volumeClaimTemplates[?(@.metadata.name=="data")].spec.resources.requests.storage} {.spec.volumeClaimTemplates[?(@.metadata.name=="data")].spec.accessModes[0]}')" \
    "1Gi ReadWriteOnce"
  check_eq "data is mounted at /var/lib/postgresql/data" \
    "$(jp -n $NS sts database-cluster '{.spec.template.spec.containers[0].volumeMounts[?(@.name=="data")].mountPath}')" \
    "/var/lib/postgresql/data"
  check_eq "3 pods are Ready" "$(jp -n $NS sts database-cluster '{.status.readyReplicas}')" "3"
  local i
  for i in 0 1 2; do
    check_eq "PVC data-database-cluster-$i is Bound" "$(jp -n $NS pvc data-database-cluster-$i '{.status.phase}')" "Bound"
  done
  check "database-cluster-0.database-cluster.$NS.svc.cluster.local resolves" \
    probe "$NS" - "nslookup database-cluster-0.database-cluster.$NS.svc.cluster.local"
}
