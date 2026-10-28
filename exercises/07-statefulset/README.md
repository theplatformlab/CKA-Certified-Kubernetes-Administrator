# Exercise 07 — StatefulSet Deployment

> Related: [README — Workloads and Scheduling](../../README.md#domain-1--workloads-and-scheduling-15)

Deploy a stateful application using StatefulSet. This exercise teaches ordered pod initialization, persistent storage, and stable network identities—critical for databases and distributed systems on the CKA.

## Context

StatefulSets are for applications that need:
- Stable, predictable pod names (not randomly generated like Deployments)
- Ordered pod startup and shutdown
- Persistent storage per pod replica
- Stable network identities (DNS names with ordinal suffixes)

Unlike Deployments where pod identity doesn't matter, StatefulSets maintain identity across restarts. Example: a database cluster needs predictable names like `web-0`, `web-1`, `web-2` that survive pod recreations.

## Tasks

Work in namespace `exercise-07` (`./scripts/lab.sh setup 07` creates it).

1. Create a headless Service named `web`:
   - selector `app=web`
   - port `80`, named `http`
2. Create a StatefulSet named `web`:
   - `serviceName: web`, 3 replicas, pod label `app=web`
   - one container named `nginx`, image `nginx:1.28`, containerPort `80` named `http`
   - a `volumeClaimTemplates` entry named `www`, `ReadWriteOnce`, `1Gi`, using the default StorageClass, mounted at `/usr/share/nginx/html`
3. Watch the pods start in order (`web-0` first, then `web-1`, then `web-2`) and confirm each pod got its own PVC (`www-web-0`, ...)
4. Write each pod's own name into its volume: `/usr/share/nginx/html/index.html` of `web-0` must contain `web-0`, and so on
5. Delete pod `web-1` and confirm it comes back with the same name and still serves `web-1`
6. Scale the StatefulSet to 5 replicas, then back to 3, and watch the reverse-order termination
7. From a test pod, confirm `curl web-0.web.exercise-07.svc.cluster.local` returns `web-0`

Validate with `./scripts/lab.sh check 07`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Headless Service: set `spec.clusterIP: None` in the Service definition
- StatefulSet pods get DNS names like `nginx-0.nginx.default.svc.cluster.local`
- Use `.spec.serviceName` to reference the headless Service
- `.spec.volumeClaimTemplates` automatically creates a PVC for each replica
- Pod ordinals matter: `web-0` runs before `web-1` (controlled by `podManagementPolicy: OrderedReady`)
- `k get pvc` will show each pod's persistent claim

</details>

## What tripped me up

> I initially thought StatefulSet worked like Deployment with just named pods. Wrong. When I deleted the Service, the StatefulSet was still there but the pods lost their DNS names. Then I couldn't reach web-0 by name from other pods. The headless Service is not optional—it's the foundation for stable identities.
>
> Another gotcha: when you scale down a StatefulSet, pods are terminated in reverse order (web-2, then web-1, then web-0). This is important for graceful shutdown in databases. I scaled down expecting random termination, but it follows the spec.
>
> PVC persistence is real: when you delete the StatefulSet, the PVCs don't automatically delete. If you create a new StatefulSet with the same name and storage class, the pods will bind to their old volumes and recover data. I skipped this step on my first attempt and didn't understand why data persisted.

## Verify

```bash
./scripts/lab.sh check 07
```

Manual checks:

```bash
k -n exercise-07 get svc web                  # CLUSTER-IP must be None
k -n exercise-07 get sts web                  # 3/3 ready
k -n exercise-07 get pods -l app=web -o wide
k -n exercise-07 get pvc                      # www-web-0, www-web-1, www-web-2 Bound
k -n exercise-07 run t --image=busybox:1.37 --rm -it --restart=Never -- \
  wget -qO- web-0.web.exercise-07.svc.cluster.local
```

## Cleanup

```bash
./scripts/lab.sh cleanup 07
```

Before cleaning up, try this: delete the StatefulSet (`k -n exercise-07 delete sts web`) and notice that the PVCs stay. Recreate the StatefulSet and each pod gets its old volume back, including its `index.html`.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: exercise-07
spec:
  clusterIP: None  # This makes it headless
  selector:
    app: web
  ports:
  - name: http
    port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
  namespace: exercise-07
spec:
  serviceName: web
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.28
        ports:
        - containerPort: 80
          name: http
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

```bash
k apply -f sts.yaml
k -n exercise-07 get pods -w            # web-0, then web-1, then web-2

# Give every pod its own content
for i in 0 1 2; do
  k -n exercise-07 exec web-$i -- sh -c 'hostname > /usr/share/nginx/html/index.html'
done

# Identity and storage survive a pod deletion
k -n exercise-07 delete pod web-1
k -n exercise-07 exec web-1 -- cat /usr/share/nginx/html/index.html   # web-1

# Scale up and down
k -n exercise-07 scale sts web --replicas=5
k -n exercise-07 scale sts web --replicas=3   # web-4 goes first, then web-3

# Stable DNS name per pod
k -n exercise-07 run t --image=busybox:1.37 --rm -it --restart=Never -- \
  wget -qO- web-0.web.exercise-07.svc.cluster.local
```

</details>
