# Mock Exam 02 — CKA Practice (Kubernetes 1.35)

Duration: 2 hours (120 minutes)
Questions: 15
Passing Score: 66% (approximately 10 questions correct)

Do not look at the solutions until you complete this exam.

---

## Question 1: Service Discovery and DNS

An application in namespace `backend` needs to call a service in namespace `frontend` via DNS. The service name is `web-ui` and it exposes port 3000.

The application's configuration needs the full DNS name to connect. What is the correct DNS name within the cluster that the backend application should use?

Also, verify that pod-to-pod DNS resolution works using nslookup or dig from a test pod.

**Time: 6 minutes**


## Question 2: Deployment Rolling Update and Rollback

A deployment `payment-service` has been updated with a new image version that introduced a bug. Users are reporting errors. You need to:
1. Check the deployment's rollout history
2. Identify which revision had the issue
3. Rollback to the previous stable version
4. Verify the rollback completed successfully

**Time: 8 minutes**


## Question 3: Secrets and Environment Variables

A pod needs access to database credentials:
- Username: `dbuser`
- Password: `secret123`
- Database: `appdb`

Create a Secret and mount it in a deployment pod as environment variables (not as files).

Verify that the pod can access these environment variables without exposing them in pod logs.

**Time: 7 minutes**


## Question 4: DaemonSet Configuration

A monitoring agent needs to run on every node in the cluster, including control plane nodes. Currently, some nodes are missing the agent due to taints.

Create or update a DaemonSet to:
1. Run the `datadog/agent:latest` image on all nodes
2. Tolerate the taint `node-role.kubernetes.io/control-plane:NoSchedule`
3. Verify the agent is running on all nodes

**Time: 8 minutes**


## Question 5: Cluster API Server Debugging

The API server appears to be responding slowly. You need to:
1. Check the API server logs for errors or warnings
2. Verify the API server is listening on port 6443
3. Check if there are too many requests from a specific source
4. Review the audit trail for suspicious activity

Provide the commands you would use to debug this issue.

**Time: 9 minutes**


## Question 6: ConfigMap Updates and Pod Restarts

A ConfigMap contains application configuration that was just updated. Pods currently running the application still have the old configuration because they mounted the ConfigMap at pod startup.

Implement a solution to ensure pods pick up the new configuration without manually restarting them. Consider using volume reload mechanisms or automation.

**Time: 8 minutes**


## Question 7: PriorityClass and Pod Eviction

Set up a cluster with different priority levels:
1. Create a PriorityClass for critical workloads with priority 1000
2. Create a PriorityClass for standard workloads with priority 100
3. Deploy two critical pods and one standard pod
4. When the node runs out of memory, verify the standard pod is evicted before critical pods

Briefly explain the preemption policy.

**Time: 9 minutes**


## Question 8: Service Types and Exposure

A legacy application needs to be accessible from outside the cluster on a specific port. Internal services use ClusterIP, but this application needs external access without using Ingress.

Create a Service of the appropriate type that:
1. Exposes the pod on an external IP
2. Uses port 8080 on the node and routes to port 3000 on the pod
3. Verify external connectivity

**Time: 7 minutes**


## Question 9: CronJob Scheduling

Set up a backup job that should run:
1. Every day at 2 AM
2. Keep only the last 3 successful job runs
3. Suspend the CronJob (it should not run for the next month)
4. Start it again when needed

Create the CronJob manifest and verify the schedule settings.

**Time: 7 minutes**


## Question 10: Cluster Certificate Rotation

The cluster's certificate-based authentication is expiring soon. You need to:
1. Check the current certificate expiration date
2. Renew the certificates using kubeadm
3. Verify the new certificates are in place
4. Ensure the API server is using the new certificates

Provide the commands needed for certificate rotation.

**Time: 10 minutes**


## Question 11: Pod Disruption Budgets

An application deployment runs 10 replicas and cannot lose more than 2 pods simultaneously during cluster disruptions (maintenance, node failures).

Create a PodDisruptionBudget that enforces this constraint. Test the budget by attempting to drain a node with multiple application pods.

**Time: 8 minutes**


## Question 12: Custom Resource Definitions (CRD)

Your team has created a custom CRD called `Database` to represent database instances. A developer needs to:
1. Check if the CRD already exists
2. Create an instance of the custom resource
3. Verify the custom resource is stored in etcd
4. Delete the custom resource

Provide the commands to interact with the custom resource.

**Time: 7 minutes**


## Question 13: Pod Security Policy Bypass

A pod in the `restricted` namespace requires elevated permissions (to run as root). Currently, Pod Security Standards enforce a restricted policy.

1. Create an exception for this specific pod using pod-security.kubernetes.io labels
2. Allow the pod to run with elevated privilege
3. Verify other pods in the namespace still follow the restrictive policy

**Time: 9 minutes**


## Question 14: Storage Class and Dynamic Provisioning

Configure dynamic volume provisioning:
1. Create a StorageClass with the SSD provisioner
2. Create a PVC that requests 20Gi
3. Verify that PV is automatically created and bound
4. Deploy a pod that uses the dynamically provisioned volume

**Time: 8 minutes**


## Question 15: Namespace Quota and Resource Management

Set up resource governance for the `batch-jobs` namespace:
1. Limit total CPU to 10 cores
2. Limit total memory to 20Gi
3. Set per-pod minimum: 500m CPU, 256Mi memory
4. Set per-pod maximum: 4 CPU, 8Gi memory
5. Test by trying to deploy a pod that exceeds limits and verify it's rejected

**Time: 10 minutes**

---

## End of Mock Exam 02

Total Time: 120 minutes

After completing, review your answers against the solutions provided in `MOCK-EXAM-02-SOLUTIONS.md`.
