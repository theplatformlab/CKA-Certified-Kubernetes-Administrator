# Mock Exam 02 — CKA Practice (Kubernetes 1.37)

Duration: 2 hours (120 minutes)
Questions: 15
Passing Score: 66% (approximately 10 questions correct)

Do not look at the solutions until you complete this exam.

---

## Question 1: Service Discovery and DNS

A Deployment in namespace `backend` cannot reach the `web-ui` Service in namespace `frontend`, which exposes TCP port 3000.

1. Determine the Service's fully qualified DNS name and the short cross-namespace name
2. From a temporary Pod in `backend`, verify DNS resolution and connect to the Service
3. If DNS resolves but the connection fails, inspect the Service endpoints and identify the next likely cause

**Time: 6 minutes**


## Question 2: Deployment Rollback

The Deployment `payment-service` in namespace `prod` was updated to a faulty image. Roll back to the previous revision.

1. Inspect rollout history and identify the previous revision
2. Roll back to that revision
3. Verify the rollout completed and confirm the image now in use

**Time: 8 minutes**


## Question 3: Secret as Environment Variables

The Deployment `app-deploy` in namespace `apps` needs database credentials supplied as environment variables.

Create a Secret named `db-creds` with:
- `username`: `dbuser`
- `password`: `secret123`
- `database`: `appdb`

Update the Deployment so the container receives these values as `DB_USERNAME`, `DB_PASSWORD`, and `DB_DATABASE`. Verify the variables are present without printing their values or exposing them in logs.

**Time: 7 minutes**


## Question 4: DaemonSet Tolerations

A DaemonSet named `monitoring-agent` in namespace `monitoring` should run on every Linux node, including control-plane nodes. The DaemonSet is already configured with its container and node selector, but its Pods are missing from control-plane nodes.

Add the required toleration for `node-role.kubernetes.io/control-plane:NoSchedule` and verify the DaemonSet has a Pod on each eligible node. Do not change the image.

**Time: 8 minutes**


## Question 5: API Server Troubleshooting

The API server on the control-plane node is intermittently slow. Investigate without changing cluster configuration:
1. Check API server Pod status, recent logs, and readiness
2. Check node and etcd health indicators available in the cluster
3. If audit logging is configured, inspect recent failed or unusually frequent requests and identify the requesting user
4. Report findings; do not enable new audit logging as part of this task

**Time: 9 minutes**


## Question 6: Apply a ConfigMap Update

The Deployment `catalog` in namespace `apps` mounts a ConfigMap named `catalog-config` as a volume. The ConfigMap has been updated, but the application has not reloaded the new configuration.

Trigger a safe rolling restart of the Deployment, then verify the new Pods are Ready and the updated file is mounted. Do not install a third-party reloader.

**Time: 8 minutes**


## Question 7: PriorityClass and Scheduling

Create two PriorityClasses:
- `critical-workload` with value `1000`
- `standard-workload` with value `100`

Assign two Pods to the critical class and one Pod to the standard class. Verify their assigned priorities and briefly explain how priority affects scheduling and preemption.

Do not induce node memory pressure. Priority does not guarantee a particular kubelet memory-pressure eviction order.

**Time: 9 minutes**


## Question 8: Expose a Service with NodePort

A Deployment in namespace `legacy` has Pods labeled `app=legacy` listening on TCP port 3000. Expose it externally without Ingress.

Create a NodePort Service named `legacy-app` with:
- Service port 3000
- Target port 3000
- NodePort 30080

Verify the Service has endpoints and, if the lab network permits, test `http://<node-ip>:30080` from outside the cluster.

**Time: 7 minutes**


## Question 9: CronJob Schedule and Suspension

Create a CronJob named `daily-backup` in namespace `ops` that runs a placeholder backup command (`echo backup started`) every day at 02:00 UTC. Keep the three most recent successful Jobs and suspend scheduled runs for now.

Verify its schedule, timezone, history limit, and suspended state. Then resume it by updating the CronJob.

**Time: 7 minutes**


## Question 10: Renew kubeadm Certificates

On the control-plane node of a kubeadm cluster:
1. Check certificate expiration
2. Renew the cluster certificates using kubeadm
3. Restart the relevant static control-plane Pods safely so they load renewed certificates
4. Recheck certificate expiration and confirm the API server is healthy

Follow the cluster's maintenance procedure and perform this only in the designated lab environment.

**Time: 10 minutes**


## Question 11: Pod Disruption Budget

The Deployment `web` in namespace `apps` has 10 Ready replicas labeled `app=web`. It must retain at least 8 available Pods during voluntary disruptions.

Create a PodDisruptionBudget with the appropriate selector and availability requirement. Inspect its status, then attempt to drain a worker with multiple `web` Pods. If the budget prevents eviction, explain why and what must become available before the drain can complete.

**Time: 8 minutes**


## Question 12: Work with a Custom Resource

The cluster has an existing CRD named `databases.example.com`. The lab provides a valid sample `Database` resource manifest for that CRD.

1. Check whether the CRD is installed and discover the served API version
2. Apply the provided custom resource
3. Verify it through the Kubernetes API
4. Delete the custom resource

Do not attempt to query etcd directly.

**Time: 7 minutes**


## Question 13: Pod Security Admission

Create a namespace named `restricted` and configure Pod Security Admission to enforce and warn on the `restricted` standard.

1. Create a Pod named `restricted-pod` that complies with the standard
2. Attempt to create a privileged Pod named `blocked-pod`
3. Confirm that enforcement rejects the privileged Pod

**Time: 9 minutes**


## Question 14: Dynamic Volume Provisioning

The lab cluster provides an SSD-capable StorageClass named `fast-ssd` with a working provisioner.

1. Create a 20Gi PVC using `fast-ssd`
2. Create a Pod that mounts the claim at `/data`
3. Verify the claim binds and the Pod mounts the volume

Do not create or modify the cluster's StorageClass or provisioner.

**Time: 8 minutes**


## Question 15: Namespace Quota and LimitRange

Create namespace `batch-jobs` and configure:
- A ResourceQuota limiting total requested CPU to 10 cores and requested memory to 20Gi
- A LimitRange requiring each container to request at least 500m CPU and 256Mi memory, and limiting it to at most 4 CPU and 8Gi memory

Verify the policies, then attempt to create a Pod whose request and limit exceed the per-container maximum and confirm admission rejects it.

**Time: 9 minutes**

---

## End of Mock Exam 02

Total Time: 120 minutes

After completing, review your answers against the solutions provided in `MOCK-EXAM-02-SOLUTIONS.md`.
