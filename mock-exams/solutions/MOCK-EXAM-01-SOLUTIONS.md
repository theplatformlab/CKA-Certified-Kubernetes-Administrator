# Mock Exam 01 — Solutions

---

## Solution 1: Pod Deployment Troubleshooting

Create ConfigMap:
```bash
k create configmap app-config --from-literal=config.yaml='database_host: postgres.production.svc.cluster.local' -n production
```

Or more naturally, create the file first:
```bash
echo 'database_host: postgres.production.svc.cluster.local' > config.yaml
k create configmap app-config --from-file=config.yaml -n production
```

Update pod manifest to mount ConfigMap. The pod's `volumes` section should reference the ConfigMap, and the container's `volumeMounts` should mount it:

```yaml
spec:
  containers:
  - name: app
    image: your-image
    volumeMounts:
    - name: config-volume
      mountPath: /etc/app
  volumes:
  - name: config-volume
    configMap:
      name: app-config
      items:
      - key: config.yaml
        path: config.yaml
```

Verify:
```bash
k get pod app-frontend -n production
k exec app-frontend -n production -- cat /etc/app/config.yaml
```

**Key insight:** The pod was crashing because the file didn't exist. ConfigMap mounts it at the expected path. The `items` field ensures the key name matches the file name.

---

## Solution 2: RBAC and Service Account

Create Role:
```bash
k create role list-resources --verb=list --resource=pods,deployments -n staging
```

Create RoleBinding:
```bash
k create rolebinding dev-user-binding --role=list-resources --user=dev-user -n staging
```

Verify permissions:
```bash
k auth can-i list pods --as=dev-user -n staging
k auth can-i list deployments --as=dev-user -n staging
k auth can-i list pods --as=dev-user -n production  # Should be denied
```

**Key insight:** RoleBinding is namespace-scoped. `--as=dev-user` tests permissions for that user. The user cannot list pods in other namespaces because the Role only applies to `staging`.

---

## Solution 3: Node Maintenance

Cordon the node:
```bash
k cordon worker-2
```

Drain the node but exclude static pods (which can't be evicted):
```bash
k drain worker-2 --ignore-daemonsets --delete-emptydir-data
```

If the database pod has a local persistent volume and shouldn't be evicted, add `--skip-wait-for-delete-timeout`:
```bash
k drain worker-2 --ignore-daemonsets --delete-emptydir-data --force
```

Verify node is cordoned:
```bash
k get node worker-2  # Should show NotReady,SchedulingDisabled
```

After maintenance, uncordon:
```bash
k uncordon worker-2
```

**Key insight:** `cordon` prevents new pods from scheduling. `drain` evicts existing pods. Daemonsets pods need `--ignore-daemonsets` because they manage themselves. Pods with local storage may need `--force` to evict.

---

## Solution 4: Persistent Volume Configuration

Assuming you need a ReadWriteMany storage class for multiple pods:

Create StorageClass (if `fast-ssd` doesn't exist):
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
allowVolumeExpansion: true
```

Create PVC:
```bash
k create pvc db-storage --size=5Gi --storageclass=fast-ssd --access-modes=ReadWriteMany -n databases
```

Or YAML:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-storage
  namespace: databases
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 5Gi
```

Update deployment `db-app` to mount the PVC:
```bash
k set volume deployment/db-app -n databases --add --mount-path=/data --type=persistentVolumeClaim --claim-name=db-storage
```

Or edit and add to spec:
```yaml
volumeMounts:
- name: data-volume
  mountPath: /data
...
volumes:
- name: data-volume
  persistentVolumeClaim:
    claimName: db-storage
```

Verify:
```bash
k get pvc -n databases
k describe pod -n databases  # Should show mapped volume
```

**Key insight:** ReadWriteMany is needed if multiple pods use the same storage. PVC claims the storage from the pool. The deployment mounts it at `/data`.

---

## Solution 5: Network Policy Troubleshooting

Frontend policy (allow inbound on port 80):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  ingress:
  - protocol: TCP
    ports:
    - port: 80
```

Backend policy (allow inbound from frontend on port 3000):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - protocol: TCP
    ports:
    - port: 3000
    from:
    - podSelector:
        matchLabels:
          tier: frontend
```

Database policy (allow inbound from backend on port 5432):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: shop
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - protocol: TCP
    ports:
    - port: 5432
    from:
    - podSelector:
        matchLabels:
          tier: backend
```

Apply all three policies:
```bash
k apply -f frontend-policy.yaml -f backend-policy.yaml -f database-policy.yaml -n shop
```

**Key insight:** NetworkPolicy uses label selectors to specify both source and destination. The `from` field restricts incoming traffic to only those pods. All three policies work together to enforce the communication flow.

---

## Solution 6: Helm Chart Deployment

Create namespace:
```bash
k create namespace monitoring
```

Deploy Helm chart with overrides:
```bash
helm install monitoring-stack ./helm-charts/monitoring \
  -n monitoring \
  --set replica_count=3 \
  --set storage_size=50Gi \
  --set persistence=true
```

Verify deployment:
```bash
helm list -n monitoring
k get deployment -n monitoring
```

**Key insight:** `--set` overrides values in the chart's `values.yaml`. Multiple `--set` flags can be chained. `helm list` shows installed releases by name.

---

## Solution 7: Container Runtime Configuration

On each worker node, update kubelet config:

```bash
ssh worker-node
sudo nano /etc/kubernetes/kubelet.conf
```

Add or update:
```yaml
containerRuntimeEndpoint: unix:///var/run/cri-dockerd.sock
```

Restart kubelet:
```bash
sudo systemctl restart kubelet
```

Verify the runtime:
```bash
k get nodes -o wide
k describe node workeŕ-1  # Check Runtime Version should show docker
```

Test with a pod:
```bash
k run test-pod --image=nginx
k get pod test-pod -o wide
```

**Key insight:** CRI-dockerd listens on a Unix socket at `/var/run/cri-dockerd.sock`. Kubelet must be told where to find it. After restart, pods should run on CRI-dockerd.

---

## Solution 8: API Server Audit Logs

Enable audit logging in kube-apiserver. On the control plane node:

```bash
sudo nano /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add audit policy file and log output:
```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit.log
    - --audit-log-maxage=7
  ...
  volumeMounts:
  - name: audit
    mountPath: /var/log/kubernetes
  volumes:
  - name: audit
    hostPath:
      path: /var/log/kubernetes
```

Create audit policy:
```bash
sudo nano /etc/kubernetes/audit-policy.yaml
```

Policy to log ConfigMap access:
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["configmaps"]
  namespaces: ["default"]
- level: Metadata
  resources:
  - group: ""
    resources: ["configmaps"]
```

Review logs:
```bash
sudo tail -f /var/log/kubernetes/audit.log | jq '.[] | select(.objectRef.resource=="configmaps")'
```

**Key insight:** Audit logs capture who did what and when. By filtering for ConfigMaps in the `default` namespace, you can identify unauthorized access patterns.

---

## Solution 9: HPA and Application Scaling

Create HPA:
```bash
k autoscale deployment web-app -n production --min=2 --max=10 --cpu-percent=70
```

Or YAML for more control:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app-hpa
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
```

Verify HPA:
```bash
k get hpa -n production
k describe hpa web-app-hpa -n production
kubectl top pods -n production   # confirms metrics-server is working
```

**Key insight:** HPA uses a single target utilization, not separate scale-up and scale-down thresholds. On each sync it computes `desiredReplicas = ceil(currentReplicas × currentCPU / targetCPU)` and scales in either direction within the `minReplicas`/`maxReplicas` bounds. A built-in tolerance (default 10%) prevents action on minor fluctuations, and scale-down aggressiveness can be tuned via `spec.behavior.scaleDown` (e.g. `stabilizationWindowSeconds`) rather than any fixed percentage. HPA requires `metrics-server` to be running.

---

## Solution 10: Ingress Configuration with TLS

Create Ingress:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
spec:
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls-cert
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /api/
        pathType: Prefix
        backend:
          service:
            name: api
            port:
              number: 80
      - path: /health
        pathType: Exact
        backend:
          service:
            name: api
            port:
              number: 80
```

Apply Ingress:
```bash
k apply -f ingress.yaml
```

Verify:
```bash
k get ingress
k describe ingress api-ingress
```

**Key insight:** TLS is configured at the Ingress level. Both `/api/*` and `/health` routes go to the same service. The health endpoint doesn't need special handling; all traffic is TLS-terminated at the Ingress. The service backend receives unencrypted traffic.

---

## Solution 11: Cluster Troubleshooting

Check control plane components:
```bash
k get pods -n kube-system | grep scheduler
k describe pod -n kube-system kube-scheduler-controlplane
k logs -n kube-system kube-scheduler-controlplane
```

Check kubelet logs on control plane:
```bash
ssh controlplane
sudo journalctl -u kubelet -n 50
sudo journalctl -u kubelet -p err
```

Common causes:
- Scheduler CrashLoopBackOff: usually a configuration issue in `/etc/kubernetes/manifests/kube-scheduler.yaml`
- Static pod not starting: check manifest syntax
- Kubelet can't read manifest: permissions issue

Restart kubelet:
```bash
sudo systemctl restart kubelet
```

Verify scheduler is running:
```bash
k get pods -n kube-system kube-scheduler-controlplane
k get pods  # Verify new pods are being scheduled
```

**Key insight:** If `kube-scheduler` static pod crashes, no pods can be scheduled. Check kubelet logs to see why the manifest isn't loading. Static pods are in `/etc/kubernetes/manifests/` on the control plane node.

---

## Solution 12: StatefulSet with Persistent Storage

Create StatefulSet:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database-cluster
spec:
  serviceName: database-cluster
  replicas: 3
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: db-storage
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: db-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: database-cluster
spec:
  clusterIP: None
  selector:
    app: database
  ports:
  - port: 5432
    targetPort: 5432
```

Apply:
```bash
k apply -f statefulset.yaml
```

Verify:
```bash
k get statefulset
k get pods -o wide  # Should see database-cluster-0, database-cluster-1, database-cluster-2
k get pvc  # Each pod should have its own PVC
```

**Key insight:** `volumeClaimTemplates` creates a unique PVC for each pod. `serviceName: database-cluster` links to the headless service. Pod DNS names are `database-cluster-0.database-cluster`, etc.

---

## Solution 13: Resource Quotas and Limits

Create ResourceQuota:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: test-quota
  namespace: test
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "4"
    limits.memory: 8Gi
```

Create LimitRange:
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: test-limits
  namespace: test
spec:
  limits:
  - min:
      cpu: 100m
      memory: 128Mi
    type: Pod
```

Apply both:
```bash
k apply -f resourcequota.yaml -f limitrange.yaml -n test
```

Test deployment of a pod requesting 2 CPUs and 2Gi memory:
```bash
k run test-pod --image=nginx --requests='cpu=2,memory=2Gi' -n test
```

This should be rejected:
```
Error from server (Forbidden): pods "test-pod" is forbidden: exceeded quota: test-quota
```

Verify quotas and limits:
```bash
k describe resourcequota test-quota -n test
k describe limitrange test-limits -n test
```

**Key insight:** ResourceQuota limits the namespace total. LimitRange limits individual pods. Together, they prevent resource exhaustion at namespace and pod levels.

---

## Solution 14: Pod Security Standards

Update namespace to enforce PSS:
```bash
k label namespace restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline
```

Or via YAML:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: restricted
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
```

Test with a privileged pod:
```bash
k run priv-pod --image=nginx --privileged -n restricted
```

Expected result:
```
Error from server (Forbidden): pods "priv-pod" is forbidden:
violates PodSecurityPolicy: privileged: true
```

**Key insight:** Enforcement (`enforce`) blocks pods that violate the policy. Audit and warn levels log violations but allow them. `restricted` PSS requires no privileged containers, read-only root filesystem, etc.

---

## Solution 15: Multi-Container Pod with Sidecar

Create pod:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-logger
spec:
  containers:
  - name: nginx
    image: nginx:1.28
    volumeMounts:
    - name: log-volume
      mountPath: /var/log/nginx
  - name: logger
    image: busybox:1.37
    command: ["/bin/sh"]
    args: ["-c", "tail -f /logs/access.log"]
    volumeMounts:
    - name: log-volume
      mountPath: /logs
  volumes:
  - name: log-volume
    emptyDir: {}
```

Apply:
```bash
k apply -f pod-with-sidecar.yaml
```

Verify:
```bash
k get pod app-with-logger
k logs app-with-logger -c nginx
k logs app-with-logger -c logger
k exec app-with-logger -c logger -- ls -la /logs
```

**Key insight:** Both containers share the same `log-volume` (emptyDir). The main container writes logs to `/var/log/nginx`. The sidecar reads them from `/logs` (same mount, different path). EmptyDir storage is ephemeral and deleted when the pod terminates.

---

## Overall Scoring

Each question is worth ~6.7 points (15 questions = 100 points).
- 10+ correct = Pass (66%)
- 12+ correct = Strong performance
- 15/15 = Excellent mastery

Review the solutions that you missed and reference the corresponding exercises in the repo for deeper practice.
