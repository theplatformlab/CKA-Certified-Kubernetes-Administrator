# Mock Exam 02 — Solutions

---

## Solution 1: Service Discovery and DNS

The correct DNS name format within a cluster is:
```
<service-name>.<namespace>.svc.cluster.local
```

For this case:
```
web-ui.frontend.svc.cluster.local
```

Or simply:
```
web-ui.frontend
```

Both work from within the cluster. Connect with port 3000:
```
web-ui.frontend:3000
```

Verify DNS resolution with nslookup:
```bash
k run debug-pod --image=busybox --rm -it -- nslookup web-ui.frontend
```

Or:
```bash
k run debug-pod --image=busybox --rm -it -- nslookup web-ui.frontend.svc.cluster.local
```

Expected output shows the service's Cluster IP address. From a test pod in `backend` namespace:
```bash
k run test -n backend --image=nginx --rm -it -- wget -qO- http://web-ui.frontend:3000
```

**Key insight:** DNS name includes namespace. Short names work only when querying from the same namespace. Full names work cluster-wide. CoreDNS handles this resolution automatically.

---

## Solution 2: Deployment Rolling Update and Rollback

Check rollout history:
```bash
k rollout history deployment/payment-service
```

Each revision shows the image versions. Identify the problematic revision and check details:
```bash
k rollout history deployment/payment-service --revision=3
```

Rollback to the previous revision:
```bash
k rollout undo deployment/payment-service
```

Or rollback to a specific revision:
```bash
k rollout undo deployment/payment-service --to-revision=2
```

Verify rollback status:
```bash
k rollout status deployment/payment-service
k get pods -o wide  # New pods should be coming up with old image
k describe deployment payment-service  # Check image version
```

Check the new revision history:
```bash
k rollout history deployment/payment-service
```

**Key insight:** Each update creates a new ReplicaSet. Rollback simply scales down the bad ReplicaSet and scales up the good one. Pods are recreated with old image.

---

## Solution 3: Secrets and Environment Variables

Create Secret:
```bash
k create secret generic db-creds \
  --from-literal=username=dbuser \
  --from-literal=password=secret123 \
  --from-literal=database=appdb
```

Or via YAML:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
stringData:
  username: dbuser
  password: secret123
  database: appdb
```

Update deployment to use Secret as environment variables:
```bash
k set env deployment/app-deploy --from=secret/db-creds --prefix=DB_
```

Or edit deployment to add:
```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: password
        - name: DB_DATABASE
          valueFrom:
            secretKeyRef:
              name: db-creds
              key: database
```

Verify the environment variables are available (they won't show in pod describe because they're secret):
```bash
k exec <pod-name> -- env | grep DB_
```

Check pod logs don't expose secrets:
```bash
k logs <pod-name>
```

**Key insight:** Using `valueFrom.secretKeyRef` ensures secrets aren't exposed in pod definitions. Environment variables are injected at runtime. Never echo secrets in logs.

---

## Solution 4: DaemonSet Configuration

Create DaemonSet with toleration for control plane:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: monitoring-agent
spec:
  selector:
    matchLabels:
      app: monitoring
  template:
    metadata:
      labels:
        app: monitoring
    spec:
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
      containers:
      - name: agent
        image: datadog/agent:latest
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 256Mi
```

Apply:
```bash
k apply -f daemonset.yaml
```

Verify on all nodes:
```bash
k get daemonset monitoring-agent
k get pods -o wide -l app=monitoring
```

Should see pods on control plane and all worker nodes:
```bash
k get pods -A -l app=monitoring
```

Count should match number of nodes:
```bash
k get nodes --no-headers | wc -l
```

**Key insight:** DaemonSets respect taints only if toleration is specified. Control plane has `node-role.kubernetes.io/control-plane:NoSchedule` taint by default. Without toleration, the pod won't schedule there.

---

## Solution 5: Cluster API Server Debugging

Check API server logs:
```bash
ssh controlplane
sudo journalctl -u kubelet -n 100  # Kubelet logs
sudo journalctl -u kube-apiserver -n 100  # Direct systemd service
```

Or for static pod (common in kubeadm clusters):
```bash
k logs -n kube-system kube-apiserver-controlplane
k logs -n kube-system kube-apiserver-controlplane --tail=50
```

Verify API server is listening:
```bash
netstat -tlnp | grep 6443
sudo ss -tlnp | grep apiserver
curl -k https://localhost:6443
```

Check for audit events if audit logging is enabled:
```bash
sudo tail -f /var/log/kubernetes/audit.log | jq '.[] | select(.responseStatus.code >= 500)'
```

Look for request patterns:
```bash
sudo tail -f /var/log/kubernetes/audit.log | jq '.[] | .user.username' | sort | uniq -c
```

Check load on API server:
```bash
k top nodes
k top pods -n kube-system | grep apiserver
```

Identify slow requests:
```bash
sudo tail -f /var/log/kubernetes/audit.log | jq '.[] | select(.requestReceivedTimestamp < .responseReceivedTimestamp) | .responseReceivedTimestamp - .requestReceivedTimestamp'
```

**Key insight:** API server logs are usually in journalctl for systemd or as a static pod in `-n kube-system`. High latency often indicates etcd performance issues or excessive requests from a client.

---

## Solution 6: ConfigMap Updates and Pod Restarts

Problem: ConfigMap is mounted as a volume, but changes don't immediately reflect in running pods.

Solution 1 — Manual pod restart:
```bash
k rollout restart deployment/my-app
```

This recreates all pods which reload the ConfigMap.

Solution 2 — Automatic reloader (Stakater Reloader):
This is a third-party tool but shows the pattern:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  config.yaml: |
    key: value
```

Annotation on deployment:
```yaml
spec:
  template:
    metadata:
      annotations:
        configmap.reloader.stakater.com/match: "app-config"
```

When ConfigMap changes, the reloader updates pod annotations, triggering a rollout.

Solution 3 — Ignore for now (reload on next deployment):
Some teams accept that ConfigMap changes require manual redeploy. Document this as a known limitation.

For immediate needs:
```bash
k patch configmap app-config -p '{"data":{"config":"new-value"}}'
k rollout restart deployment/my-app
```

**Key insight:** Kubernetes doesn't automatically restart pods when ConfigMaps change. Volume mounts may update over time (depends on kubelet settings), but the best practice is explicit restart or a reloader controller.

---

## Solution 7: PriorityClass and Pod Eviction

Create critical PriorityClass:
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical
value: 1000
globalDefault: false
description: "Critical priority workloads"
preemptionPolicy: PreemptLowerPriority
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: standard
value: 100
globalDefault: true
description: "Standard priority workloads"
preemptionPolicy: PreemptLowerPriority
```

Deploy critical pods with priority:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-pod-1
spec:
  priorityClassName: critical
  containers:
  - name: app
    image: nginx
```

Deploy standard pod:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: standard-pod
spec:
  priorityClassName: standard
  containers:
  - name: app
    image: nginx
```

When node runs out of memory, kublet evicts pods in priority order. If `preemptionPolicy: PreemptLowerPriority`, higher priority pods can preempt lower ones.

Verify by checking which pods remain:
```bash
k get pods
```

Standard pod should be evicted before critical pods.

**Key insight:** PriorityClass value (higher number = higher priority). PreemptionPolicy controls whether higher priority pods can evict lower ones. Without preemption, priority only affects scheduling order.

---

## Solution 8: Service Types and Exposure

Use NodePort Service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-app
spec:
  type: NodePort
  selector:
    app: legacy
  ports:
  - protocol: TCP
    port: 3000        # Internal pod port
    targetPort: 3000  # Pod listens on this
    nodePort: 8080    # External node port
```

Apply:
```bash
k apply -f service.yaml
```

Verify:
```bash
k get svc legacy-app
```

Output shows:
```
NAME         TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
legacy-app   NodePort   10.100.100.100  <none>        3000:8080/TCP    5s
```

Access externally:
```bash
curl http://<node-ip>:8080
```

Verify from outside cluster:
```bash
curl http://192.168.1.10:8080  # Where 192.168.1.10 is a node IP
```

**Key insight:** NodePort opens a port on every node. External traffic comes to node:port, then kube-proxy routes to the pod. Port range is typically 30000-32767 (unless custom), but can specify any port in that range.

---

## Solution 9: CronJob Scheduling

Create CronJob:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-job
spec:
  schedule: "0 2 * * *"  # Every day at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  suspend: false
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
            command: ["/bin/sh", "-c", "echo 'Running backup'; sleep 5"]
          restartPolicy: OnFailure
```

Apply:
```bash
k apply -f cronjob.yaml
```

Verify the schedule:
```bash
k get cronjob backup-job
k describe cronjob backup-job
```

Suspend the CronJob (won't run for next month):
```bash
k patch cronjob backup-job -p '{"spec":{"suspend":true}}'
```

Resume when needed:
```bash
k patch cronjob backup-job -p '{"spec":{"suspend":false}}'
```

Check successful job history:
```bash
k get jobs -l cronjob-name=backup-job
```

**Key insight:** CronJob schedule uses cron syntax (minute hour day month dayOfWeek). `0 2 * * *` = 2 AM daily. `successfulJobsHistoryLimit: 3` keeps only last 3 successful jobs; older ones are deleted automatically.

---

## Solution 10: Cluster Certificate Rotation

Check current certificate expiration:
```bash
sudo kubeadm certs check-expiration
```

Output shows each certificate and when it expires.

Renew all certificates:
```bash
sudo kubeadm certs renew all
```

Check they were renewed:
```bash
sudo kubeadm certs check-expiration
```

Restart the API server and other control plane components to pick up new certs:
```bash
sudo systemctl restart kubelet
```

Or if static pods:
```bash
kubectl -n kube-system delete pod kube-apiserver-<controlplane>
```

Kubelet will automatically recreate it with the new manifest and certs.

Verify API server is using new certs:
```bash
openssl s_client -connect localhost:6443 </dev/null | openssl x509 -noout -dates
```

Check the notAfter date matches the renewed date.

**Key insight:** Kubeadm manages certificate renewal. Certificates are typically valid for 1 year from cluster initialization. Renewal doesn't require cluster restart, but API server must reload (usually happens when the pod is deleted/recreated).

---

## Solution 11: Pod Disruption Budgets

Create PodDisruptionBudget:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
spec:
  minAvailable: 8
  selector:
    matchLabels:
      app: my-app
```

This means: at least 8 pods must stay available during disruption. With 10 replicas, only 2 can be disrupted simultaneously.

Apply:
```bash
k apply -f pdb.yaml
```

Verify:
```bash
k get pdb
k describe pdb app-pdb
```

Test by draining a node with multiple app pods:
```bash
k drain worker-1 --ignore-daemonsets
```

Without the PDB, all app pods on this node would be evicted.
With the PDB, Kubernetes respects minAvailable and evicts pods gradually, ensuring at least 8 are always running.

Monitor drain progress:
```bash
k get pods
k get nodes worker-1
```

**Key insight:** PDB is a soft constraint — it prevents voluntary disruptions (maintenance, scaling) but not hardware failures. Node failure immediately deletes pods and breaks PDB constraints.

---

## Solution 12: Custom Resource Definitions (CRD)

Check if CRD exists:
```bash
k get crd databases.example.com  # Specific CRD name
k get crd | grep database
```

Create custom resource instance:
```yaml
apiVersion: example.com/v1
kind: Database
metadata:
  name: prod-db
spec:
  engine: postgres
  version: "15"
  storage: 100Gi
```

Apply:
```bash
k apply -f database-instance.yaml
```

Verify in etcd and API server:
```bash
k get databases
k describe database prod-db
k get database prod-db -o yaml
```

Delete the resource:
```bash
k delete database prod-db
```

Or by name:
```bash
k delete database --all
```

**Key insight:** CRDs extend the Kubernetes API with custom resources. Commands work the same as built-in resources. Data is stored in etcd like any other resource.

---

## Solution 13: Pod Security Policy Bypass

Create an exception for a privileged pod using pod-security labels:

Option 1 — Pod-level exception:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
  namespace: restricted
  labels:
    pod-security.kubernetes.io/exempt: 'true'
spec:
  containers:
  - name: app
    image: nginx
    securityContext:
      privileged: true
```

Option 2 — Exemption at pod level (if supported by PSS version):
```bash
k label pod privileged-pod -n restricted pod-security.kubernetes.io/exempt=true
```

Verify the pod runs with elevated privilege:
```bash
k get pod privileged-pod -n restricted
k exec privileged-pod -- id
```

Verify other pods still follow restrict policy:
```bash
k run normal-pod --image=nginx -n restricted
# This pod should fail to start if it tries to be privileged
```

Check PSS labels on namespace:
```bash
k get namespace restricted --show-labels
```

**Key insight:** Pod security exceptions are label-based. Only pods with the exemption label bypass the policy. Other pods continue to be enforced.

---

## Solution 14: Storage Class and Dynamic Provisioning

Create StorageClass:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd-provisioner
provisioner: pd.csi.storage.gke.io  # GKE example; varies by cluster
parameters:
  type: pd-ssd
allowVolumeExpansion: true
reclaimPolicy: Delete
```

Apply:
```bash
k apply -f storageclass.yaml
```

Create PVC:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-ssd-claim
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ssd-provisioner
  resources:
    requests:
      storage: 20Gi
```

Apply:
```bash
k apply -f pvc.yaml
```

Verify PV is created automatically:
```bash
k get pvc my-ssd-claim
k get pv  # Should see a new PV bound to the PVC
```

Deploy a pod using the PVC:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-using-ssd
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: ssd-volume
      mountPath: /data
  volumes:
  - name: ssd-volume
    persistentVolumeClaim:
      claimName: my-ssd-claim
```

Apply and verify:
```bash
k apply -f pod.yaml
k get pods
k exec app-using-ssd -- df -h /data  # Should show 20Gi mount
```

**Key insight:** StorageClass enables dynamic provisioning. When PVC is created, the provisioner automatically creates a matching PV. Pod binds to the PVC, which is bound to the PV.

---

## Solution 15: Namespace Quota and Resource Management

Create ResourceQuota:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: batch-jobs-quota
  namespace: batch-jobs
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "10"
    limits.memory: 20Gi
```

Create LimitRange:
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: batch-jobs-limits
  namespace: batch-jobs
spec:
  limits:
  - type: Container
    min:
      cpu: 500m
      memory: 256Mi
    max:
      cpu: 4
      memory: 8Gi
```

Apply both:
```bash
k apply -f quota.yaml -f limitrange.yaml -n batch-jobs
```

Verify:
```bash
k describe quota -n batch-jobs
k describe limits -n batch-jobs
```

Test by deploying a pod that exceeds limits:
```bash
k run oversized-pod \
  -n batch-jobs \
  --image=nginx \
  --requests='cpu=8,memory=16Gi' \
  --overrides='{"spec":{"containers":[{"resources":{"limits":{"cpu":"8","memory":"16Gi"}}}]}}'
```

Should be rejected:
```
Error: the container cannot be created because the request exceeds the allocation set by the LimitRange
```

Or:
```
Error: the deployment violates the ResourceQuota: requests.cpu and memory exceeded
```

Try again with acceptable values:
```bash
k run compliant-pod \
  -n batch-jobs \
  --image=nginx \
  --requests='cpu=2,memory=4Gi'
```

Should succeed.

**Key insight:** LimitRange applies to individual containers. ResourceQuota applies to the whole namespace. Together they prevent resource exhaustion at both pod and namespace levels.

---

## Overall Scoring

Each question is worth ~6.7 points (15 questions = 100 points).
- 10+ correct = Pass (66%)
- 12+ correct = Strong performance
- 15/15 = Excellent mastery

If you scored lower, identify weak areas and reference the corresponding exercises. If you scored high on both exams, you're ready for the real CKA exam.
