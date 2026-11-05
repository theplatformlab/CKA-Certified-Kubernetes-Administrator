# Mock Exam 02 — Solutions (Kubernetes 1.37)

These solutions target the repository's stated CKA environment, Kubernetes 1.37. They assume the resources named in each task already exist unless the question says to create them. Cluster-specific facilities such as metrics, storage provisioners, audit policies, and external network access must be provided by the lab.

---

## Solution 1: Service Discovery and DNS

The fully qualified Service DNS name is:

```text
web-ui.frontend.svc.cluster.local
```

The short cross-namespace form from a Pod in `backend` is `web-ui.frontend`. Verify DNS and connectivity from a temporary Pod:

```bash
kubectl run dns-check -n backend --rm -i --restart=Never \
  --image=busybox:1.36 -- nslookup web-ui.frontend.svc.cluster.local

kubectl run service-check -n backend --rm -i --restart=Never \
  --image=busybox:1.36 -- wget -qO- http://web-ui.frontend:3000/
```

If the name resolves but the request fails, inspect the Service selector, ready Pods, and endpoints:

```bash
kubectl describe service web-ui -n frontend
kubectl get pods -n frontend --show-labels
kubectl get endpoints web-ui -n frontend
kubectl get endpointslices -n frontend \
  -l kubernetes.io/service-name=web-ui
```

**Key insight:** DNS resolution proves the Service name resolves, not that it has ready endpoints or that the application is listening on the target port.

---

## Solution 2: Deployment Rollback

Inspect the rollout history and revision details:

```bash
kubectl rollout history deployment/payment-service -n prod
kubectl rollout history deployment/payment-service -n prod --revision=<revision>
```

Roll back one revision, or choose the known-good revision explicitly:

```bash
kubectl rollout undo deployment/payment-service -n prod
# Or:
kubectl rollout undo deployment/payment-service -n prod --to-revision=<good-revision>
```

Verify rollout status and the image in the Deployment template:

```bash
kubectl rollout status deployment/payment-service -n prod
kubectl get deployment payment-service -n prod \
  -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'
kubectl rollout history deployment/payment-service -n prod
```

**Key insight:** Rollback creates a new rollout revision using the prior Pod template. Use revision details to select the intended known-good version rather than guessing a revision number.

---

## Solution 3: Secret as Environment Variables

Create the Secret in the same namespace as the Deployment. For real credentials, avoid committing plaintext values or placing them in shell history; use an approved secret-management workflow.

```bash
kubectl create secret generic db-creds -n apps \
  --from-literal=username=dbuser \
  --from-literal=password=secret123 \
  --from-literal=database=appdb
```

Add explicit environment variable references to the Deployment's container:

```yaml
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

Apply the updated Deployment and verify the Pod template rolled out:

```bash
kubectl rollout status deployment/app-deploy -n apps
kubectl get pods -n apps
```

Check the variables exist without printing their values:

```bash
kubectl exec -n apps deployment/app-deploy -- sh -c \
  'test -n "$DB_USERNAME" && test -n "$DB_PASSWORD" && test -n "$DB_DATABASE"'
```

The command exits successfully if all variables are non-empty and does not display the credentials. Do not log or print their values.

**Key insight:** `secretKeyRef` injects selected Secret keys into the container environment. Environment variables are set when a container starts, so changing the Secret alone does not update existing container environments.

---

## Solution 4: DaemonSet Tolerations

Inspect the DaemonSet and node taints, then add a toleration to its Pod template. For example, edit the DaemonSet:

```bash
kubectl edit daemonset monitoring-agent -n monitoring
```

Add under `spec.template.spec` while preserving any existing tolerations:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

Verify the DaemonSet rollout and its placement:

```bash
kubectl rollout status daemonset/monitoring-agent -n monitoring
kubectl get daemonset monitoring-agent -n monitoring
kubectl get pods -n monitoring -o wide
kubectl get nodes --show-labels
kubectl describe node <control-plane-node>
```

Compare the DaemonSet's desired number with eligible nodes. A node selector, affinity rule, or other untolerated taint can still prevent scheduling.

**Key insight:** A toleration allows a Pod to schedule onto a matching tainted node; it does not force scheduling or override node selectors and affinity.

---

## Solution 5: API Server Troubleshooting

Check control-plane Pod status and recent API server logs:

```bash
kubectl get pods -n kube-system -o wide | grep kube-apiserver
kubectl logs -n kube-system <kube-apiserver-pod> --since=10m
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
```

On the control-plane node, check kubelet logs and resource pressure:

```bash
sudo journalctl -u kubelet -n 100 --no-pager
kubectl describe node <control-plane-node>
kubectl top node <control-plane-node>
```

Check etcd Pod health and logs when that component is available in the lab:

```bash
kubectl get pods -n kube-system -l component=etcd -o wide
kubectl logs -n kube-system <etcd-pod> --since=10m
```

If audit logging is already configured, locate the configured audit log path from the API server manifest and inspect recent failed requests. For a JSON-lines audit log:

```bash
sudo jq 'select(.stage == "ResponseComplete" and
  .responseStatus.code >= 400) |
  {time: .requestReceivedTimestamp,
   user: .user.username,
   verb,
   resource: .objectRef.resource,
   namespace: .objectRef.namespace,
   name: .objectRef.name,
   code: .responseStatus.code}' <audit-log-path>
```

Summarize repeated requests by authenticated user only after selecting relevant events. Do not enable audit logging or change API server configuration during this diagnostic task.

**Key insight:** Check readiness, logs, node pressure, and etcd health before assuming the API server itself is the root cause. Audit data is available only if the cluster already collects it.

---

## Solution 6: Apply a ConfigMap Update

Trigger a rolling restart of the Deployment so the application process reloads the mounted configuration:

```bash
kubectl rollout restart deployment/catalog -n apps
kubectl rollout status deployment/catalog -n apps
```

Verify new Pods are Ready and inspect the mounted configuration file without changing it:

```bash
kubectl get pods -n apps -l app=catalog
kubectl exec -n apps deployment/catalog -- cat <mount-path>/<config-file>
```

Use the actual labels, mount path, and filename from the Deployment. Confirm the mounted file contains the updated value specified in the lab.

**Key insight:** A ConfigMap mounted as a volume is eventually projected into the Pod, but the application may not watch or reload the file. A rollout restart is a straightforward way to ensure the process starts with the updated configuration.

---

## Solution 7: PriorityClass and Scheduling

Create the two PriorityClasses:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical-workload
value: 1000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: standard-workload
value: 100
globalDefault: false
preemptionPolicy: PreemptLowerPriority
```

Create the requested Pods with `priorityClassName` set in each Pod spec. For example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-1
  namespace: default
spec:
  priorityClassName: critical-workload
  containers:
    - name: app
      image: registry.k8s.io/pause:3.9
---
apiVersion: v1
kind: Pod
metadata:
  name: critical-2
  namespace: default
spec:
  priorityClassName: critical-workload
  containers:
    - name: app
      image: registry.k8s.io/pause:3.9
---
apiVersion: v1
kind: Pod
metadata:
  name: standard-1
  namespace: default
spec:
  priorityClassName: standard-workload
  containers:
    - name: app
      image: registry.k8s.io/pause:3.9
```

Verify the classes and Pod priorities:

```bash
kubectl get priorityclass
kubectl get pods -o custom-columns=NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIORITY:.spec.priority
```

**Key insight:** Higher priority affects scheduling order and can enable scheduler preemption of lower-priority Pods when a higher-priority Pod cannot fit. Priority alone does not guarantee a specific kubelet memory-pressure eviction order; resource requests and usage, quality of service, and node conditions also matter.

---

## Solution 8: Expose a Service with NodePort

Create the Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: legacy-app
  namespace: legacy
spec:
  type: NodePort
  selector:
    app: legacy
  ports:
    - name: http
      protocol: TCP
      port: 3000
      targetPort: 3000
      nodePort: 30080
```

Apply and verify endpoints:

```bash
kubectl apply -f legacy-app-service.yaml
kubectl get service legacy-app -n legacy
kubectl get endpoints legacy-app -n legacy
kubectl get pods -n legacy -l app=legacy -o wide
```

From a host that can reach a node's IP and the NodePort:

```bash
curl http://<node-ip>:30080
```

The default NodePort range includes `30080`. External reachability depends on the lab network and firewall configuration.

**Key insight:** `port` is the Service port, `targetPort` is the Pod port, and `nodePort` is opened on cluster nodes. A NodePort Service does not itself create a public external IP.

---

## Solution 9: CronJob Schedule and Suspension

Create the suspended CronJob with an explicit UTC schedule:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-backup
  namespace: ops
spec:
  schedule: "0 2 * * *"
  timeZone: "Etc/UTC"
  suspend: true
  successfulJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: busybox:1.36
              command: ["sh", "-c", "echo backup started"]
```

Apply and inspect:

```bash
kubectl apply -f daily-backup-cronjob.yaml
kubectl get cronjob daily-backup -n ops -o yaml
kubectl describe cronjob daily-backup -n ops
```

Resume scheduled runs when appropriate:

```bash
kubectl patch cronjob daily-backup -n ops --type=merge \
  -p '{"spec":{"suspend":false}}'
```

**Key insight:** `suspend: true` prevents future scheduled Jobs; it does not delete Jobs that already exist. `timeZone: Etc/UTC` makes the intended schedule explicit.

---

## Solution 10: Renew kubeadm Certificates

On the control-plane node, inspect expiration and renew the certificates managed by kubeadm:

```bash
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all
sudo kubeadm certs check-expiration
```

Renewal does not automatically reload every certificate into already-running static control-plane Pods. Follow the cluster's maintenance procedure to restart the control-plane static Pods one at a time. In a single-control-plane lab, the general mechanism is to temporarily move the relevant manifest out of `/etc/kubernetes/manifests/`, wait for the static Pod to stop, then move the manifest back and wait for it to become healthy. Keep the API server available between component restarts where possible, and do not leave backup manifests in the watched directory.

After restart, verify the control-plane Pods and API server health:

```bash
kubectl get pods -n kube-system -o wide
kubectl get --raw='/readyz?verbose'
sudo kubeadm certs check-expiration
```

For HA clusters, renew and restart one control-plane node at a time according to the cluster's operational runbook. Certificate authority certificates are not renewed by `kubeadm certs renew all`.

**Key insight:** Check the actual certificate inventory and expiry first. Static Pods must reload renewed files, and certificate renewal is a maintenance operation that can affect control-plane availability.

---

## Solution 11: Pod Disruption Budget

Create a PDB selecting the Deployment's Pods:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
  namespace: apps
spec:
  minAvailable: 8
  selector:
    matchLabels:
      app: web
```

Apply and inspect its status:

```bash
kubectl apply -f web-pdb.yaml
kubectl get pdb web-pdb -n apps
kubectl describe pdb web-pdb -n apps
kubectl get pods -n apps -l app=web -o wide
```

In the designated lab, attempt to drain a node containing multiple matching Pods:

```bash
kubectl drain <worker-node> --ignore-daemonsets --timeout=2m
```

The eviction API can evict Pods only while the PDB's disruption budget allows. If 8 Pods are already available, further voluntary eviction is blocked until a disrupted Pod is healthy again or the workload has enough additional healthy replicas. Do not bypass the PDB with a force option for the purpose of this exercise.

**Key insight:** A PDB constrains voluntary disruptions submitted through the eviction API. It does not prevent involuntary node failures, and a drain can remain blocked if the minimum availability cannot be maintained.

---

## Solution 12: Work with a Custom Resource

Check whether the CRD exists and discover served versions:

```bash
kubectl get crd databases.example.com
kubectl get crd databases.example.com \
  -o jsonpath='{range .spec.versions[?(@.served==true)]}{.name}{"\n"}{end}'
kubectl api-resources --api-group=example.com
```

Use the lab-provided sample manifest, including the exact `apiVersion` and fields accepted by the installed CRD:

```bash
kubectl apply -f database-sample.yaml
kubectl get databases.example.com
kubectl get databases.example.com <resource-name> -o yaml
```

Delete the test resource when finished:

```bash
kubectl delete -f database-sample.yaml
```

**Key insight:** A custom resource is managed through the Kubernetes API once its CRD is installed. Confirm the served API version and schema from the CRD or the provided sample; do not assume that resource names or spec fields are universal. Direct etcd inspection is unnecessary for verifying the resource.

---

## Solution 13: Pod Security Admission

Create and label the namespace:

```bash
kubectl create namespace restricted
kubectl label namespace restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
```

A compliant Pod can use a non-root user, the RuntimeDefault seccomp profile, no privilege escalation, and no added capabilities:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
  namespace: restricted
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: pause
      image: registry.k8s.io/pause:3.9
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
```

Apply it, then attempt the privileged Pod:

```bash
kubectl apply -f restricted-pod.yaml
kubectl run blocked-pod -n restricted --image=nginx:1.25 \
  --restart=Never --overrides='{"spec":{"containers":[{"name":"blocked-pod","image":"nginx:1.25","securityContext":{"privileged":true}}]}}'
```

The second request should be rejected by enforcement. The admission response should also contain a warning because the namespace has the matching `warn` label.

**Key insight:** `enforce` rejects violating Pods. `warn` reports the violation to the requesting client; it does not override or weaken enforcement.

---

## Solution 14: Dynamic Volume Provisioning

Create a PVC that uses the lab-provided StorageClass:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fast-ssd-claim
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 20Gi
```

Create a Pod that mounts the claim:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: storage-check
  namespace: default
spec:
  containers:
    - name: web
      image: nginx:1.25
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: fast-ssd-claim
```

Apply both manifests and verify provisioning and mount:

```bash
kubectl apply -f fast-ssd-claim.yaml
kubectl apply -f storage-check-pod.yaml
kubectl get pvc fast-ssd-claim
kubectl get pv
kubectl wait --for=condition=Ready pod/storage-check --timeout=120s
kubectl exec storage-check -- df -h /data
```

With `WaitForFirstConsumer`, the claim may remain Pending until the Pod is scheduled. If it does not bind, inspect the PVC events and the provisioner rather than modifying the provided StorageClass.

**Key insight:** A PVC triggers dynamic provisioning only when the StorageClass provisioner is functional and supports the requested capacity/access mode. Provisioner implementation and storage parameters are environment-specific.

---

## Solution 15: Namespace Quota and LimitRange

Create the namespace and apply a quota for aggregate requested resources plus a per-container LimitRange:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: batch-jobs
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: batch-jobs-quota
  namespace: batch-jobs
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
---
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
        cpu: "4"
        memory: 8Gi
```

Apply the policy and inspect it:

```bash
kubectl apply -f batch-jobs-policy.yaml
kubectl describe resourcequota batch-jobs-quota -n batch-jobs
kubectl describe limitrange batch-jobs-limits -n batch-jobs
```

Use a Pod manifest with requests and limits above the per-container maximum but below the aggregate quota, to isolate the LimitRange rejection:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: oversized-pod
  namespace: batch-jobs
spec:
  restartPolicy: Never
  containers:
    - name: app
      image: nginx:1.25
      resources:
        requests:
          cpu: "5"
          memory: 9Gi
        limits:
          cpu: "5"
          memory: 9Gi
```

Apply it and confirm admission rejects it because its container exceeds the LimitRange maximum:

```bash
kubectl apply -f oversized-pod.yaml
```

**Key insight:** ResourceQuota limits aggregate namespace usage; LimitRange constrains individual containers. The test requests 5 CPU and 9Gi, which is below the empty namespace's total quota but above the per-container maximum.

---

## Overall Scoring

Each question is worth approximately 6.7 points (15 questions = 100 points).
- 10+ correct = Pass (66%)
- 12+ correct = Strong performance
- 15/15 = Excellent mastery

Review missed solutions and complete the corresponding exercises in the repository for deeper practice.
