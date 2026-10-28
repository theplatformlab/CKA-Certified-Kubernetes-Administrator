# Mock Exam 01 — Solutions

Don't read this before you finish the exam. Grade first (`./scripts/mock-exam.sh grade`), then compare.

Every solution starts with the context switch from the question. On the real exam, forgetting it is the most expensive mistake there is.

---

## Question 1 — Fix a crashing pod with a ConfigMap

```bash
k config use-context kind-cka-exam
k -n production logs app-frontend          # FATAL: /etc/app/config.yaml not found

k -n production create configmap app-config \
  --from-literal=config.yaml='database_host: postgres.production.svc.cluster.local'
```

Pod volumes are immutable, so edit the saved manifest and replace the pod:

```yaml
# ~/cka-exam/q01/app-frontend.yaml (added parts)
spec:
  containers:
  - name: app
    # ... image and command unchanged ...
    volumeMounts:
    - name: config
      mountPath: /etc/app
  volumes:
  - name: config
    configMap:
      name: app-config
```

```bash
k replace --force -f ~/cka-exam/q01/app-frontend.yaml
k -n production exec app-frontend -- cat /etc/app/config.yaml
```

Mounting the whole ConfigMap at `/etc/app` is fine, because the key name becomes the file name. If `/etc/app` held other files, you would use `mountPath: /etc/app/config.yaml` with `subPath: config.yaml` instead.

---

## Question 2 — RBAC for a user and a ServiceAccount

```bash
k config use-context kind-cka-exam
k -n staging create role dev-reader --verb=get,list,watch --resource=pods,deployments
k -n staging create serviceaccount ci-bot
k -n staging create rolebinding dev-reader-binding --role=dev-reader \
  --user=dev-user --serviceaccount=staging:ci-bot

k auth can-i list deployments -n staging --as dev-user                      # yes
k auth can-i list pods -n default --as dev-user                             # no
k auth can-i list deployments -n staging --as system:serviceaccount:staging:ci-bot   # yes
```

`--resource=deployments` resolves to `deployments.apps`. A Role and RoleBinding only grant access inside their namespace. That is what keeps `dev-user` out of other namespaces.

---

## Question 3 — Node maintenance

```bash
k config use-context kind-cka-exam
k drain cka-exam-worker2 --ignore-daemonsets --delete-emptydir-data --force

k -n maintenance get pods -o wide            # shop-api pods now on other nodes
k get pods -A -o wide --field-selector spec.nodeName=cka-exam-worker2   # only DaemonSet pods
```

- `--ignore-daemonsets` is needed because DaemonSet pods can't be evicted (kube-proxy, kindnet).
- `--delete-emptydir-data` is needed because `scratch` uses an emptyDir.
- `--force` is needed because `scratch` has no controller, so drain must delete it for good.

Don't uncordon. The question wants the node to stay in maintenance.

---

## Question 4 — Static PersistentVolume

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: db-pv
spec:
  capacity:
    storage: 5Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd
  hostPath:
    path: /mnt/data/db
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-pvc
  namespace: databases
spec:
  accessModes: [ReadWriteMany]
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 5Gi
```

```bash
k config use-context kind-cka-exam
k apply -f q4.yaml
k -n databases edit deploy db-app
```

```yaml
    spec:
      containers:
      - name: app
        # ...
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: db-pvc
```

With `WaitForFirstConsumer`, the PVC stays `Pending` until a pod uses it. That is expected, not an error. hostPath volumes don't enforce access modes, so RWX works here. In production you would use NFS or CephFS for real RWX.

---

## Question 5 — NetworkPolicies for a three-tier app

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: shop
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes: [Ingress]
  ingress:
  - ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 3000
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
```

- An ingress rule with `ports` but no `from` allows that port from everywhere, which is what the frontend needs.
- A `podSelector` inside `from` without a `namespaceSelector` only matches pods in the policy's own namespace.
- Only ingress is restricted, so DNS (egress) keeps working.

Test it:

```bash
k -n shop run t --rm -it --image=busybox:1.37 --labels=tier=frontend --restart=Never -- wget -qO- -T 3 backend:3000
```

---

## Question 6 — Install a local Helm chart

```bash
k config use-context kind-cka-exam
helm show values ~/cka-exam/helm-charts/monitoring      # find the value names
helm install monitoring-stack ~/cka-exam/helm-charts/monitoring \
  -n monitoring --create-namespace \
  --set replicaCount=3 \
  --set persistence.enabled=true \
  --set persistence.size=2Gi

helm -n monitoring list
helm -n monitoring get values monitoring-stack
k -n monitoring get deploy,pvc
```

If you installed it with the wrong values, fix them with `helm upgrade monitoring-stack ... --set ...`, then `--reuse-values`. Don't edit `values.yaml`.

---

## Question 7 — Kubelet and container runtime

```bash
k config use-context kind-cka-exam-ops
k get nodes                                  # cka-exam-ops-worker NotReady
ssh cka-exam-ops-worker

systemctl status kubelet                     # activating (auto-restart), disabled
journalctl -u kubelet -n 20 --no-pager       # ... endpoint "unix:///run/cri-dockerd.sock": no such file

grep -rn cri-dockerd /var/lib/kubelet/config.yaml /var/lib/kubelet/kubeadm-flags.env /etc/default/kubelet 2>/dev/null
sed -i 's|unix:///run/cri-dockerd.sock|unix:///run/containerd/containerd.sock|' /var/lib/kubelet/config.yaml
systemctl enable --now kubelet
systemctl restart kubelet
exit

k get nodes -w
```

Runtime settings can live in three places: `/var/lib/kubelet/config.yaml` (`containerRuntimeEndpoint`), `/var/lib/kubelet/kubeadm-flags.env` (`--container-runtime-endpoint`) and `/etc/default/kubelet`. Check all three. "Starts on boot" means `systemctl enable`.

---

## Question 8 — API server audit logging

```bash
k config use-context kind-cka-exam-ops
ssh cka-exam-ops-control-plane
mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]
- level: Request
  namespaces: ["default"]
  resources:
  - group: ""
    resources: ["configmaps"]
- level: None
EOF
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=7
    - --audit-log-maxbackup=3
    # ... existing flags ...
    volumeMounts:
    - name: audit-policy
      mountPath: /etc/kubernetes/audit
      readOnly: true
    - name: audit-log
      mountPath: /var/log/kubernetes/audit
  volumes:
  - name: audit-policy
    hostPath:
      path: /etc/kubernetes/audit
      type: DirectoryOrCreate
  - name: audit-log
    hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
```

```bash
# wait for the apiserver to come back (30-60s)
watch crictl ps --name kube-apiserver
tail -n 2 /var/log/kubernetes/audit/audit.log
```

Rule order matters: the first rule that matches wins, so the catch-all `level: None` goes last. Without the volume mounts, the apiserver can't read the policy or write the log, and it won't start. If it doesn't come back, check `crictl ps -a` and `crictl logs <id>`, or `/var/log/pods/kube-system_kube-apiserver-*`.

---

## Question 9 — HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
```

`k autoscale deploy web-app --cpu-percent=70 --min=2 --max=10 -n production $do > hpa.yaml` gives you the skeleton. The `behavior` block has to be added by hand.

---

## Question 10 — Ingress with TLS

```bash
k config use-context kind-cka-exam
k -n api create ingress api-ingress --class=nginx \
  --rule="api.example.com/api*=api:8080,tls=api-tls-cert" \
  --rule="api.example.com/health=api:8080" $do > ing.yaml
```

Check the result: `/api*` becomes `pathType: Prefix` and `/health` becomes `Exact`.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: api
spec:
  ingressClassName: nginx
  tls:
  - hosts: [api.example.com]
    secretName: api-tls-cert
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 8080
      - path: /health
        pathType: Exact
        backend:
          service:
            name: api
            port:
              number: 8080
```

No ingress controller runs in the exam cluster, so only the resource is graded.

---

## Question 11 — Pods stuck in Pending

```bash
k config use-context kind-cka-exam-ops
k -n default describe pod -l app=rescue      # no events at all -> nothing is scheduling
k -n kube-system get pods                    # kube-scheduler in CrashLoopBackOff
k -n kube-system logs kube-scheduler-cka-exam-ops-control-plane
# ... stat /etc/kubernetes/scheduler.config: no such file or directory

ssh cka-exam-ops-control-plane
ls /etc/kubernetes/                           # scheduler.conf exists
sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.config|--kubeconfig=/etc/kubernetes/scheduler.conf|' \
  /etc/kubernetes/manifests/kube-scheduler.yaml
exit

k -n kube-system get pods -w
k -n default get pods
```

A Pending pod with no `FailedScheduling` event means no scheduler looked at it at all. Check the scheduler, not the pod.

---

## Question 12 — StatefulSet with stable storage

```yaml
apiVersion: v1
kind: Service
metadata:
  name: database-cluster
  namespace: databases
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
  namespace: databases
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
k -n databases get pods -w      # database-cluster-0, then -1, then -2
k -n databases run t --rm -it --image=busybox:1.37 --restart=Never -- \
  nslookup database-cluster-0.database-cluster.databases.svc.cluster.local
```

PGDATA points to a subdirectory because Postgres refuses to initialise a directory that isn't empty, and some volume types contain `lost+found`.

---

## Question 13 — ResourceQuota and LimitRange

```bash
k config use-context kind-cka-exam
k -n test create quota compute-quota \
  --hard=requests.cpu=4,requests.memory=8Gi,limits.cpu=4,limits.memory=8Gi
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: container-limits
  namespace: test
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    default:
      cpu: 200m
      memory: 256Mi
    min:
      cpu: 100m
      memory: 128Mi
    max:
      cpu: "1"
      memory: 1Gi
```

The 2-CPU pod is rejected by the LimitRange (`maximum cpu usage per Container is 1`), not by the quota. Once the quota covers `limits.*`, every pod has to declare limits. The LimitRange defaults fill them in, which is why a pod without resources is still admitted.

---

## Question 14 — Pod Security Standards

```bash
k config use-context kind-cka-exam
k label ns restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=baseline
k -n restricted rollout restart deploy web    # warning lists what's missing; new pods are rejected
k -n restricted edit deploy web
```

```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: nginx-unprivileged
        image: nginxinc/nginx-unprivileged:1.28-alpine
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

```bash
k -n restricted rollout status deploy web
k -n restricted run priv --image=busybox:1.37 \
  --overrides='{"spec":{"containers":[{"name":"priv","image":"busybox:1.37","securityContext":{"privileged":true}}]}}'
# Error ... violates PodSecurity "restricted:latest"
```

Labelling the namespace doesn't touch running pods. `enforce` only applies when pods are created. So check the ReplicaSet events (`k -n restricted describe rs`) after the restart.

---

## Question 15 — Native sidecar container

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-logger
  namespace: logging
spec:
  initContainers:
  - name: logger
    image: busybox:1.37
    restartPolicy: Always          # this makes it a native sidecar
    command: ["sh", "-c", "tail -F /logs/access.log"]
    volumeMounts:
    - name: logs
      mountPath: /logs
  containers:
  - name: nginx
    image: nginx:1.28
    volumeMounts:
    - name: logs
      mountPath: /var/log/nginx
  volumes:
  - name: logs
    emptyDir: {}
```

```bash
k -n logging exec app-with-logger -c nginx -- curl -s localhost >/dev/null
k -n logging logs app-with-logger -c logger
```

The nginx image links `access.log` to stdout. Mounting the emptyDir over `/var/log/nginx` hides that symlink, so nginx writes a real file the sidecar can tail. `tail -F` (capital F) keeps retrying until the file exists.
