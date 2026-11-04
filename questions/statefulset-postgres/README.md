# StatefulSet with stable storage

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `db-cluster`:

1. Create a headless Service named `database-cluster`:
   - selector `app=database-cluster`
   - port `5432`, named `postgres`
2. Create a StatefulSet named `database-cluster`:
   - 3 replicas, governed by the Service above, pod label `app=database-cluster`
   - one container named `postgres`, image `postgres:17-alpine`, container port `5432`
   - environment `POSTGRES_PASSWORD=exam-pass` and `PGDATA=/var/lib/postgresql/data/pgdata`
   - a volume claim template named `data`: `ReadWriteOnce`, `1Gi`, default StorageClass, mounted at `/var/lib/postgresql/data`

All 3 pods must be Ready. They must be resolvable as `database-cluster-0.database-cluster.db-cluster.svc.cluster.local` and so on.

## Hints

- A headless Service has `clusterIP: None`; the StatefulSet's `serviceName` must point to it.
- `volumeClaimTemplates` creates one PVC per pod, named `<template>-<pod>`.
- Postgres needs `POSTGRES_PASSWORD`, and PGDATA in a subdirectory of the mount.

## Solution

```yaml
apiVersion: v1
kind: Service
metadata:
  name: database-cluster
  namespace: db-cluster
spec:
  clusterIP: None
  selector:
    app: database-cluster
  ports:
  - name: postgres
    port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database-cluster
  namespace: db-cluster
spec:
  serviceName: database-cluster
  replicas: 3
  selector:
    matchLabels:
      app: database-cluster
  template:
    metadata:
      labels:
        app: database-cluster
    spec:
      containers:
      - name: postgres
        image: postgres:17-alpine
        ports:
        - containerPort: 5432
          name: postgres
        env:
        - name: POSTGRES_PASSWORD
          value: exam-pass
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi
```

```bash
k -n db-cluster get pods -w      # database-cluster-0, then -1, then -2
k -n db-cluster run t --rm -it --image=busybox:1.37 --restart=Never -- \
  nslookup database-cluster-0.database-cluster.db-cluster.svc.cluster.local
```

PGDATA points to a subdirectory because Postgres refuses to initialise a directory that isn't empty, and some volume types contain `lost+found`.
