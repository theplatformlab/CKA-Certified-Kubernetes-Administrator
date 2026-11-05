# Mock Exam 01 — CKA Practice (Kubernetes 1.37)

Duration: 2 hours (120 minutes)
Questions: 15
Passing Score: 66% (approximately 10 questions correct)

Do not look at the solutions until you complete the exam.

---

## Question 1: Fix a CrashLoopBackOff Deployment

The deployment `payments-api` in namespace `prod` is stuck in `CrashLoopBackOff`.

Investigate the pod and identify the root cause. Then fix the configuration so the application starts successfully.

Requirements:
1. The application expects a configuration file at `/etc/app/app.env`
2. The file content must include the setting `DB_HOST=postgres.prod.svc.cluster.local`
3. The pod should start and become Ready without manual container restarts

The deployment manifest already exists. You only need to fix the configuration.

**Time: 7 minutes**


## Question 2: Service Selector Mismatch

The application `web` in namespace `dev` is not reachable through its Service even though the Deployment exists and the Pods are Running.

Your task:
1. Inspect the Service and Deployment labels
2. Identify why the Service has no endpoints
3. Fix the selector mismatch
4. Verify the Service resolves traffic to the pod successfully

Use `kubectl get endpoints`, `kubectl describe svc`, and `kubectl get pods -o wide` to confirm the fix.

**Time: 8 minutes**


## Question 3: Namespace-Scoped RBAC

A junior engineer needs permission to list Pods and Deployments only in the `staging` namespace. They must not be able to view resources in other namespaces.

Create:
1. A `Role` named `staging-reader`
2. A `RoleBinding` that grants the user `dev-user` access in `staging`

Verify with `kubectl auth can-i list pods --namespace staging --as dev-user` and `kubectl auth can-i list pods --namespace default --as dev-user`.

**Time: 6 minutes**


## Question 4: Prepare a Node for Maintenance

Node `worker-2` needs maintenance. There are multiple pods on the node, including one critical database pod whose only data copy is on local storage and must not be evicted or interrupted.

Perform the required maintenance preparation:
1. Mark the node unschedulable
2. Evict or move the non-critical workloads safely
3. Ensure the database pod is not evicted
4. Identify whether the node can safely be taken offline now, and state what must happen before it can be shut down

Use the correct drain strategy and explain why this is safe.

**Time: 7 minutes**


## Question 5: Persistent Storage with a StorageClass

An application in namespace `data` needs a persistent volume of 5Gi that can be mounted by multiple pods at the same time. The lab environment provides an RWX-capable StorageClass named `fast-rwx`.

Create the required resources:
1. Inspect the provided `fast-rwx` StorageClass and determine whether dynamic provisioning is available
2. Create a `PersistentVolumeClaim` of 5Gi using that class
3. Create a `PersistentVolume` only if the lab requires static provisioning and supplies backend details
4. Update the Deployment `db-app` to mount the volume at `/data`

Requirements:
- Access mode should allow multiple pods to read and write concurrently
- The application must start successfully with the mounted volume

**Time: 9 minutes**


## Question 6: Restrict Network Traffic in a Namespace

The namespace `shop` currently allows unrestricted communication between all Pods. You must enforce a basic least-privilege policy.

Implement NetworkPolicies so that:
1. Pods labeled `app=frontend` can receive HTTP traffic on port 80 from Pods in the `shop` namespace
2. Pods labeled `app=backend` accept traffic from `app=frontend` only on port 8080
3. Pods labeled `app=database` accept traffic from `app=backend` only on port 5432
4. No other ingress should be allowed

Test the policies using a pod from the same namespace where needed.

**Time: 9 minutes**


## Question 7: Horizontal Pod Autoscaler

The deployment `web-app` in namespace `prod` currently runs with 2 replicas. The application normally uses CPU, and you need to scale automatically to handle load.

Create a `HorizontalPodAutoscaler` that:
1. Maintains an average CPU utilization of 60%
2. Keeps the minimum replicas at 2
3. Keeps the maximum replicas at 8

Verify the HPA is created and can scale the deployment based on CPU usage.

**Time: 7 minutes**


## Question 8: Ingress with TLS and Host Routing

The service `api-server` in namespace `apps` must be exposed through an Ingress resource.

Create an Ingress that:
1. Uses hostname `api.example.com`
2. Serves TLS using the secret `api-tls-cert`
3. Routes `/api` to service `api-server` on port 80
4. Routes `/health` to the same backend

Assume the TLS secret already exists and that the Ingress controller is installed.

**Time: 7 minutes**


## Question 9: StatefulSet with Stable Identity

Deploy a StatefulSet named `redis-cluster` in namespace `db` with the following requirements:
1. 3 replicas
2. Each pod gets a stable network identity such as `redis-cluster-0.redis-cluster.db.svc.cluster.local`
3. Pods use a headless Service named `redis-cluster`
4. Each pod has a 10Gi PVC mounted at `/data`

Verify that the pods come up in order and that each has its own persistent volume.

**Time: 9 minutes**


## Question 10: Resource Quotas and Admission Control

The namespace `team-a` is overcommitting resources. You need to enforce a quota and a default minimum request policy.

Create:
1. A `ResourceQuota` that limits total requested CPU to 4 cores and requested memory to 8Gi
2. A `LimitRange` that ensures all containers request at least 100m CPU and 128Mi memory
3. A check showing that a pod requesting 5 CPU and 9Gi memory is rejected by quota admission

**Time: 8 minutes**


## Question 11: Pod Security Admission

The namespace `restricted` must enforce a secure baseline for workloads.

Configure Pod Security Admission so that:
1. `enforce` mode is set to `restricted`
2. `audit` mode is set to `baseline`
3. A pod with `securityContext.privileged: true` is rejected

Use a test pod to validate that the admission policy is working.

**Time: 8 minutes**


## Question 12: CronJob Scheduling and Retry Behavior

The cluster needs a CronJob that runs a database cleanup job every 5 minutes. The job should be reliable but should not keep retrying forever.

Create a CronJob named `db-cleanup` in namespace `ops` with:
1. Schedule: `*/5 * * * *`
2. Container image: `busybox`
3. Command: `sh -c 'echo cleanup; date'`
4. `backoffLimit: 2`
5. `concurrencyPolicy: Forbid`

Trigger the job manually once and verify it completes successfully.

**Time: 8 minutes**


## Question 13: Diagnose a Node That Is Not Ready

The lab has deliberately stopped kubelet on one worker node, which is now marked `NotReady`. Identify the cause and restore the node.

Investigate:
1. `kubectl get nodes`
2. `kubectl describe node <node-name>`
3. `journalctl` or kubelet logs
4. The actual issue preventing the node from reporting ready

Start kubelet on the affected worker and confirm the node becomes `Ready` again.

**Time: 11 minutes**


## Question 14: API Server Audit Log Review

You suspect unauthorized access to ConfigMaps in the `default` namespace.

Investigate the audit logs to determine:
1. Which user or service account accessed the ConfigMaps
2. Which ConfigMap was targeted
3. Whether the access was successful
4. When the access occurred

You may need to inspect the API server configuration, audit policy, and log output.

**Time: 9 minutes**


## Question 15: Job Completion and Failure Handling

Create a Job in namespace `batch` configured for three successful completions:
1. Runs a container using `busybox`
2. Executes a script that prints the current date and exits successfully after a short delay
3. Uses `restartPolicy: Never`
4. Uses `completions: 3` and `parallelism: 1`

Verify that the Job completes and all three task Pods succeed.

**Time: 7 minutes**

---

## End of Mock Exam 01

Total Time: 120 minutes

After completing, review your answers against the solutions provided in `MOCK-EXAM-01-SOLUTIONS.md`.
