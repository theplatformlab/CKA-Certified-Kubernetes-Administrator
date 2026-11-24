# Exercise 07 — StatefulSet Deployment

> Related: [README — Workloads and Scheduling](../../README.md#domain-1--workloads-and-scheduling-15)

Deploy a stateful application using StatefulSet. This exercise teaches ordered pod initialization, persistent storage, and stable network identities—critical for databases and distributed systems on the CKA.

## Context

StatefulSets are for applications that need:
- Stable, predictable pod names (not randomly generated like Deployments)
- Ordered pod startup and shutdown
- Persistent storage per pod replica
- Stable network identities (DNS names with ordinal suffixes)

Unlike Deployments where pod identity doesn't matter, StatefulSets maintain identity across restarts. Example: a MySQL cluster needs predictable names like `mysql-0`, `mysql-1`, `mysql-2` that survive pod recreations.

## Tasks

1. Create a headless Service for the StatefulSet (required for DNS routing)
2. Create a StatefulSet with 3 replicas using the `nginx:1.28` image
3. Verify pods start in order (mysql-0 first, then mysql-1, then mysql-2)
4. Verify each pod has a persistent volume claim attached
5. Delete a pod and observe it respawn with the same name and storage
6. Scale the StatefulSet up and down using `kubectl scale`
7. Delete the StatefulSet and verify PVCs persist (data survives)

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Headless Service: set `spec.clusterIP: None` in the Service definition
- StatefulSet pods get DNS names like `nginx-0.nginx.default.svc.cluster.local`
- Use `.spec.serviceName` to reference the headless Service
- `.spec.volumeClaimTemplates` automatically creates a PVC for each replica
- Pod ordinals matter: `mysql-0` runs before `mysql-1` (controlled by `podManagementPolicy: OrderedReady`)
- `k get pvc` will show each pod's persistent claim

</details>

## What tripped me up

> I initially thought StatefulSet worked like Deployment with just named pods. Wrong. When I deleted the Service, the StatefulSet was still there but the pods lost their DNS names. Then I couldn't reach mysql-0 by name from other pods. The headless Service is not optional—it's the foundation for stable identities.
>
> Another gotcha: when you scale down a StatefulSet, pods are terminated in reverse order (mysql-2, then mysql-1, then mysql-0). This is important for graceful shutdown in databases. I scaled down expecting random termination, but it follows the spec.
>
> PVC persistence is real: when you delete the StatefulSet, the PVCs don't automatically delete. If you create a new StatefulSet with the same name and storage class, the pods will bind to their old volumes and recover data. I skipped this step on my first attempt and didn't understand why data persisted.

## Verify

```bash
# Headless Service created
k get svc mysql

# StatefulSet created
k get statefulset

# All 3 pods are Running and in order
k get pods -l app=mysql -o wide

# Each pod has storage
k get pvc

# Persistent DNS names work
k run debug --image=busybox:1.37 --rm -it --restart=Never -- nslookup mysql-0.mysql.default.svc.cluster.local

# Pod names are stable after deletion
k delete pod mysql-1
sleep 5
k get pods
# mysql-1 is recreated with the same name
```

## Cleanup

```bash
# Delete StatefulSet (pods will also be deleted)
k delete statefulset mysql

# Delete headless Service
k delete svc mysql

# Delete PVCs (volumes survive StatefulSet deletion)
k delete pvc --all
```

<details>
<summary>Solution</summary>

Create a headless Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  ports:
  - port: 3306
    name: mysql
  clusterIP: None  # This makes it headless
  selector:
    app: mysql
```

Create the StatefulSet:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

Deploy with imperative commands (if needed):

```bash
# Apply the YAML files
kubectl apply -f service.yaml
kubectl apply -f statefulset.yaml

# Watch pods start in order
k get pods -w

# Verify pod identities persist
k get pods -l app=mysql -o custom-columns=NAME:.metadata.name,IP:.status.podIP

# Check PVCs exist
k get pvc

# Test DNS
k run -it --image=busybox:1.37 --rm -- nslookup mysql-0.mysql

# Scale up
k scale statefulset mysql --replicas=4

# Scale down
k scale statefulset mysql --replicas=2
```

</details>
