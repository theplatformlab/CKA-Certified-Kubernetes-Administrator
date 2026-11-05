# Mock Exam 01 — Solutions (Kubernetes 1.37)

These solutions target the repository's stated CKA environment, Kubernetes 1.37. They assume the named namespaces and workloads exist unless the question asks you to create them. Resource provisioners, Ingress controllers, metrics-server, and audit logs depend on the cluster environment; verify what is available instead of assuming a particular cloud provider.

---

## Solution 1: Fix a CrashLoopBackOff Deployment

Start by confirming the failure and inspecting recent container output and events:

```bash
kubectl get pods -n prod -l app=payments-api
kubectl describe pod -n prod <payments-api-pod>
kubectl logs -n prod <payments-api-pod> --previous
```

The scenario's root cause is that the expected configuration file is absent. Create a ConfigMap whose key is the expected filename:

```bash
kubectl create configmap payments-api-config \
  --from-literal=app.env='DB_HOST=postgres.prod.svc.cluster.local' \
  -n prod
```

Edit the Deployment and add a mount to its existing application container:

```bash
kubectl edit deployment payments-api -n prod
```

Add the following under the existing container and Pod spec respectively:

```yaml
# Under the existing application container:
volumeMounts:
  - name: app-config
    mountPath: /etc/app
    readOnly: true

# Under spec.template.spec:
volumes:
  - name: app-config
    configMap:
      name: payments-api-config
```

Verify the rollout and mounted file:

```bash
kubectl rollout status deployment/payments-api -n prod
kubectl get pods -n prod -l app=payments-api
kubectl exec -n prod deploy/payments-api -- cat /etc/app/app.env
```

If the Deployment uses a different pod label or container setup, inspect its template and adjust the verification command. The ConfigMap key `app.env` becomes the file `/etc/app/app.env`.

**Key insight:** Diagnose from pod events and previous logs first. Fix the declarative Deployment template so replacement pods receive the configuration.

---

## Solution 2: Service Selector Mismatch

Compare the Service selector with the labels on the ready Pods:

```bash
kubectl get service web -n dev -o yaml
kubectl get deployment web -n dev --show-labels
kubectl get pods -n dev --show-labels
kubectl get endpoints web -n dev
kubectl get endpointslices -n dev -l kubernetes.io/service-name=web
```

Update the Service selector to match the Deployment's pod-template labels. For example, if the Deployment Pods have `app=web`:

```bash
kubectl patch service web -n dev --type=merge \
  -p '{"spec":{"selector":{"app":"web"}}}'
```

Use the actual labels discovered in the cluster; do not assume `app=web` if the pod template uses another label. Verify that the endpoints now contain ready Pod addresses:

```bash
kubectl get endpoints web -n dev
kubectl describe service web -n dev
```

Test the service from a Pod in `dev` using the service DNS name and its configured port, for example:

```bash
kubectl run service-check -n dev --rm -i --restart=Never \
  --image=busybox:1.36 -- wget -qO- http://web:<service-port>/
```

**Key insight:** A Service selects Pods by labels. A Running Deployment does not guarantee its Service has endpoints; readiness and selector matching both matter.

---

## Solution 3: Namespace-Scoped RBAC

Create a Role and bind it to the user in `staging`:

```bash
kubectl create role staging-reader \
  --verb=list --resource=pods,deployments.apps \
  -n staging

kubectl create rolebinding staging-reader-binding \
  --role=staging-reader --user=dev-user \
  -n staging
```

Verify the requested `list` permission and its namespace scope:

```bash
kubectl auth can-i list pods -n staging --as=dev-user
kubectl auth can-i list deployments.apps -n staging --as=dev-user
kubectl auth can-i list pods -n default --as=dev-user
```

Expected results in a clean test setup are `yes`, `yes`, and `no`. Existing ClusterRoleBindings could grant additional access, so the final check depends on the cluster's other bindings.

**Key insight:** A Role and RoleBinding grant permissions only within their namespace. Grant only the verb asked for; `list` does not imply `get`.

---

## Solution 4: Prepare a Node for Maintenance

First inspect the node and identify the database Pod, its local storage, and labels that distinguish it from workloads that may be evicted:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=worker-2
kubectl describe node worker-2
kubectl get pods -A --field-selector spec.nodeName=worker-2 --show-labels
```

Cordon the node so no new workloads are scheduled there:

```bash
kubectl cordon worker-2
```

Drain only the non-database Pods. If inspection confirms the database Pod has label `app=database`, for example:

```bash
kubectl drain worker-2 --ignore-daemonsets --pod-selector='app!=database'
```

Use the actual labels from the cluster. Do not add `--force` or `--delete-emptydir-data` as a substitute for a data-protection plan. If a suitable selector cannot isolate the database Pod, do not run a broad drain that would evict it; move other workloads individually or establish an appropriate selector first.

Verify which Pods remain on the node:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=worker-2
kubectl get node worker-2
```

**Important limitation:** If the database's only copy of data is local to `worker-2`, it cannot continue running after that node is powered off. Cordon and drain can prepare other workloads, but the node is not safe to take offline until the database data has been backed up or migrated and the service owner has approved downtime. The task's data-preservation requirement takes precedence over declaring the node ready for shutdown.

**Key insight:** `cordon` prevents new scheduling; `drain` evicts selected Pods. Local data is not protected merely by excluding a Pod from drain; plan for the workload before taking its node offline.

---

## Solution 5: Persistent Storage with a StorageClass

Check which StorageClasses and provisioners are available:

```bash
kubectl get storageclass
kubectl get pv
```

Use the environment's existing RWX-capable StorageClass named `fast-rwx`. If it is absent, the cluster administrator or lab instructions must provide the correct provisioner and parameters; a StorageClass cannot be made functional by inventing a generic provisioner name. A static PV also requires backend-specific details.

Create the claim:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-storage
  namespace: data
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fast-rwx
  resources:
    requests:
      storage: 5Gi
```

Apply it, then add the claim to the Deployment template:

```bash
kubectl apply -f db-storage-pvc.yaml
kubectl get pvc -n data
```

Edit the Deployment:

```bash
kubectl edit deployment db-app -n data
```

Add a mount to the existing application container and a PVC volume under `spec.template.spec`:

```yaml
# Under the existing application container:
volumeMounts:
  - name: data
    mountPath: /data

# Under spec.template.spec:
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: db-storage
```

Verify the rollout:

```bash
kubectl rollout status deployment/db-app -n data
```

If the Deployment already has a volume named `data`, update the pod template instead of adding a duplicate volume. Confirm the claim becomes `Bound` and inspect the Pod to confirm `/data` is mounted.

**Key insight:** `ReadWriteMany` is an access mode request, not a guarantee that the storage backend supports multi-node read/write. The provisioner must support it.

---

## Solution 6: Restrict Network Traffic in a Namespace

Apply a default-deny ingress policy first, then allow only the requested traffic to the three application tiers. NetworkPolicies are additive, so these rules provide exceptions to the default deny.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: shop
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
    - ports:
        - protocol: TCP
          port: 80
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-ingress
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: frontend
      ports:
        - protocol: TCP
          port: 3000
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: backend
      ports:
        - protocol: TCP
          port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-ingress
  namespace: shop
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 5432
```

Save and apply the manifest:

```bash
kubectl apply -f shop-network-policies.yaml
kubectl get networkpolicy -n shop
```

Test allowed and disallowed flows from Pods in the namespace. NetworkPolicy enforcement requires a CNI plugin that supports NetworkPolicy.

The empty `podSelector` in the frontend rule matches Pods in `shop`; it does not match Pods in other namespaces. NetworkPolicy enforcement depends on the CNI plugin.

---

## Solution 7: Horizontal Pod Autoscaler

Create an HPA using the stable `autoscaling/v2` API:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web-app-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: web-app
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

Apply and inspect it:

```bash
kubectl apply -f web-app-hpa.yaml
kubectl get hpa web-app-hpa -n prod
kubectl describe hpa web-app-hpa -n prod
```

CPU utilization requires CPU requests on the target containers and a working metrics API, commonly provided by metrics-server. If `TARGETS` shows `<unknown>`, inspect those dependencies before expecting scaling.

**Key insight:** The HPA computes desired replicas from observed average CPU utilization relative to the target, then clamps the result between `minReplicas` and `maxReplicas`.

---

## Solution 8: Ingress with TLS and Host Routing

Create an Ingress using `networking.k8s.io/v1`. The controller must be installed, and `api-tls-cert` must be in the same namespace as the Ingress.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-server
  namespace: apps
spec:
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-server
                port:
                  number: 80
          - path: /health
            pathType: Exact
            backend:
              service:
                name: api-server
                port:
                  number: 80
  tls:
    - hosts:
        - api.example.com
      secretName: api-tls-cert
```

Apply and verify:

```bash
kubectl apply -f api-server-ingress.yaml
kubectl describe ingress api-server -n apps
kubectl get ingress api-server -n apps
```

Both paths use the same backend. TLS termination occurs at the Ingress controller for the configured host; `/health` is not exempted from TLS by this manifest. If the requirement is to serve `/health` without TLS, it needs a separate host or controller-specific configuration and should be specified as a different task.

**Key insight:** `pathType` is required by `networking.k8s.io/v1`. Ingress path behavior beyond the API's matching rules can depend on the installed controller.

---

## Solution 9: StatefulSet with Stable Identity

Create the headless Service and StatefulSet. This example relies on a default StorageClass that supports dynamic PVC provisioning; use the lab's provided class if there is no default.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-cluster
  namespace: db
spec:
  clusterIP: None
  selector:
    app: redis-cluster
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-cluster
  namespace: db
spec:
  serviceName: redis-cluster
  replicas: 3
  selector:
    matchLabels:
      app: redis-cluster
  template:
    metadata:
      labels:
        app: redis-cluster
    spec:
      containers:
        - name: redis
          image: redis:7
          ports:
            - name: redis
              containerPort: 6379
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
```

Apply and verify:

```bash
kubectl apply -f redis-statefulset.yaml
kubectl rollout status statefulset/redis-cluster -n db
kubectl get pods,pvc -n db
kubectl get endpoints redis-cluster -n db
```

Each ordinal gets its own PVC, and the headless Service gives stable per-Pod DNS such as `redis-cluster-0.redis-cluster.db.svc.cluster.local`.

**Key insight:** `volumeClaimTemplates` creates one claim per StatefulSet Pod. StatefulSet storage and stable identity do not by themselves configure Redis replication; this task asks for Kubernetes identity and storage only.

---

## Solution 10: Resource Quotas and Admission Control

Create a quota for total requested resources and a LimitRange for the per-container minimum:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
---
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-minimums
  namespace: team-a
spec:
  limits:
    - type: Container
      min:
        cpu: 100m
        memory: 128Mi
```

Apply the policy, then create a Pod manifest whose requests exceed the quota. This is deterministic even in an otherwise empty namespace:

```bash
kubectl apply -f team-a-resource-controls.yaml
kubectl apply -f quota-check.yaml
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: quota-check
  namespace: team-a
spec:
  containers:
    - name: nginx
      image: nginx:1.25
      resources:
        requests:
          cpu: "5"
          memory: 9Gi
```

The Pod should be rejected by quota admission. Inspect the policy and usage:

```bash
kubectl describe resourcequota team-a-quota -n team-a
kubectl describe limitrange team-a-minimums -n team-a
```

**Key insight:** A request of 2 CPU and 2Gi does not exceed a 4-CPU/8-Gi quota in an empty namespace. To demonstrate rejection, the request must exceed the quota or existing namespace usage must be specified.

---

## Solution 11: Pod Security Admission

Label the existing namespace with the requested admission levels:

```bash
kubectl label namespace restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=baseline \
  --overwrite
```

Try a privileged Pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
  namespace: restricted
spec:
  containers:
    - name: test
      image: nginx:1.25
      securityContext:
        privileged: true
```

Applying this Pod should be denied by the `enforce=restricted` policy:

```bash
kubectl apply -f privileged-test.yaml
```

Pod Security Admission namespace labels are supported by the exam target. `enforce` rejects violations; `audit` records violations. `restricted` is stricter than `baseline`, so a privileged container is rejected.

---

## Solution 12: CronJob Scheduling and Retry Behavior

Create the CronJob. `backoffLimit` belongs to the Job template, not to the top-level CronJob spec.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-cleanup
  namespace: ops
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: cleanup
              image: busybox:1.36
              command: ["sh", "-c", "echo cleanup; date"]
```

Apply it, trigger an immediate run from the CronJob, and verify completion:

```bash
kubectl apply -f db-cleanup-cronjob.yaml
kubectl create job db-cleanup-manual --from=cronjob/db-cleanup -n ops
kubectl wait --for=condition=complete job/db-cleanup-manual -n ops --timeout=90s
kubectl get jobs,pods -n ops
kubectl logs job/db-cleanup-manual -n ops
```

**Key insight:** CronJobs create Jobs on a schedule. `concurrencyPolicy: Forbid` prevents a new scheduled Job from starting while the previous one is still active; it does not affect a manually created Job.

---

## Solution 13: Diagnose a Node That Is Not Ready

Confirm the node condition and the kubelet failure in the lab:

```bash
kubectl get nodes
kubectl describe node <node-name>
kubectl get events -A --sort-by=.lastTimestamp
```

On the affected worker, inspect kubelet status and recent logs:

```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100 --no-pager
```

The lab fault is a stopped kubelet. Start it on that worker, then wait for the node to recover:

```bash
sudo systemctl start kubelet
sudo systemctl status kubelet
kubectl wait --for=condition=Ready node/<node-name> --timeout=2m
kubectl describe node <node-name>
```

---

## Solution 14: API Server Audit Log Review

Inspect the control-plane API server configuration to find the audit policy and log path, then read the existing audit log. For a kubeadm static Pod, the relevant manifest is commonly `/etc/kubernetes/manifests/kube-apiserver.yaml`:

```bash
sudo grep -E -- '--audit-(policy-file|log-path)' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

Audit logs are newline-delimited JSON. Filter events for ConfigMaps in `default` and print the relevant identity, object, response, and time fields:

```bash
sudo jq 'select(.objectRef.resource == "configmaps" and
  .objectRef.namespace == "default") |
  {requestReceivedTimestamp, user: .user.username,
   verb, name: .objectRef.name, code: .responseStatus.code,
   stage}' /var/log/kubernetes/audit.log
```

Use the actual log path configured on the API server. A successful request generally has a 2xx response code; inspect `verb`, `stage`, and response status to distinguish reads, failed attempts, and duplicate audit stages.

**Key insight:** Audit events identify the authenticated user, request target, timestamp, and response status. The log path and policy are cluster configuration, not guaranteed to be the example path above.

---

## Solution 15: Job Completion and Failure Handling

Create the Job with three required completions and one Pod running at a time:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: date-report
  namespace: batch
spec:
  completions: 3
  parallelism: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: report
          image: busybox:1.36
          command: ["sh", "-c", "sleep 5; date"]
```

Apply the Job and wait for all three Pods to succeed:

```bash
kubectl apply -f date-report-job.yaml
kubectl wait --for=condition=complete job/date-report -n batch --timeout=120s
```

Verify the Job and its Pods:

```bash
kubectl get job date-report -n batch
kubectl get pods -n batch -l job-name=date-report
kubectl logs job/date-report -n batch
```

The Job controller creates three successful executions. Defining the required completion count in the manifest makes the task explicit and avoids relying on an update during an active Job.

---

## Overall Scoring

Each question is worth approximately 6.7 points (15 questions = 100 points).
- 10+ correct = Pass (66%)
- 12+ correct = Strong performance
- 15/15 = Excellent mastery

Review missed solutions and complete the corresponding exercises in the repository for deeper practice.
