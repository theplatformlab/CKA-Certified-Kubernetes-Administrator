# Mock Exam 01 — CKA Practice (Kubernetes 1.35)

Duration: 2 hours (120 minutes)
Questions: 15
Passing Score: 66% (approximately 10 questions correct)

Do not look at the solutions until you complete this exam.

---

## Question 1: Pod Deployment Troubleshooting

A pod named `app-frontend` in namespace `production` is stuck in `CrashLoopBackOff`. The pod's container is looking for a configuration file at `/etc/app/config.yaml`, but this file doesn't exist in the image.

You need to:
1. Create a ConfigMap named `app-config` with the file content: `database_host: postgres.production.svc.cluster.local`
2. Mount this ConfigMap as a file at `/etc/app/config.yaml` in the pod
3. Verify the pod starts successfully

The pod manifest already exists; you only need to update it.

**Time: 8 minutes**


## Question 2: RBAC and Service Account

A developer needs to be able to list Deployments and Pods in the `staging` namespace, but not in other namespaces. Currently, they cannot perform these actions.

Create:
1. A Role that allows listing Pods and Deployments in `staging`
2. A RoleBinding that grants this Role to the user `dev-user`

Verify the permissions work using `kubectl auth can-i`.

**Time: 7 minutes**


## Question 3: Node Maintenance

Node `worker-2` needs maintenance and will be offline for 1 hour. Currently, there are several running pods on this node including a critical database pod and a deployment with 3 replicas.

1. Prepare the node for maintenance without losing pod data
2. Ensure the database pod is NOT evicted (it has local persistent data)
3. Verify the node is ready for maintenance

**Time: 6 minutes**


## Question 4: Persistent Volume Configuration

An application needs persistent storage that:
1. Size: 5Gi
2. Access mode: can be used by multiple pods simultaneously
3. Storage class: `fast-ssd`
4. Mounted at `/data` in the pod

Create the necessary resources (StorageClass if needed, PV, PVC, and update a deployment to use it). The deployment `db-app` already exists in the `databases` namespace.

**Time: 10 minutes**


## Question 5: Network Policy Troubleshooting

Currently, all pods in namespace `shop` can communicate with each other. You need to implement network isolation:
1. Frontend pods (label: `tier=frontend`) can receive traffic on port 80 only
2. Backend pods (label: `tier=backend`) can receive traffic from frontend pods on port 3000 only
3. Database pods (label: `tier=database`) should not receive any incoming traffic except from backend pods on port 5432

Create the appropriate NetworkPolicies.

**Time: 10 minutes**


## Question 6: Helm Chart Deployment

A Helm chart named `monitoring` exists in the `helm-charts` directory locally. It has default values that need to be overridden:
- Set `replica_count` to 3
- Set `storage_size` to 50Gi
- Enable `persistence`

Deploy the chart to namespace `monitoring`. If the namespace doesn't exist, create it. The deployment should be named `monitoring-stack`.

**Time: 8 minutes**


## Question 7: Container Runtime Configuration

The cluster is having issues with container image pulls. After investigation, you realize the cluster needs to use CRI-dockerd instead of the default containerd runtime. The necessary binaries are already installed.

Configure the kubelet on worker nodes to use CRI-dockerd and verify the configuration works.

**Time: 8 minutes**


## Question 8: API Server Audit Logs

The cluster has been experiencing unauthorized API requests. You need to enable and review API server audit logs to identify:
1. Who accessed ConfigMaps in the `default` namespace
2. When the access occurred
3. Whether it was successful

Enable API server audit logging and examine the logs for ConfigMap access patterns.

**Time: 10 minutes**


## Question 9: HPA and Application Scaling

An application deployment named `web-app` in namespace `production` runs with 2 replicas. Create a Horizontal Pod Autoscaler that maintains an average CPU utilization of 70% across pods, scaling between a minimum of 2 and a maximum of 10 replicas.

**Time: 7 minutes**


## Question 10: Ingress Configuration with TLS

A service `api` needs to be exposed via Ingress with:
1. Hostname: `api.example.com`
2. TLS enabled with certificate secret `api-tls-cert`
3. Path-based routing: `/api/*` routes to the service
4. Health check endpoint at `/health` should not require TLS termination

Create the Ingress resource (assume the TLS certificate secret already exists).

**Time: 8 minutes**


## Question 11: Cluster Troubleshooting

The `kube-scheduler` component has stopped running. Investigate:
1. Check the status of all control plane components
2. Review kubelet logs on the control plane node
3. Identify why the scheduler pod is not running
4. Restart the scheduler if needed

Document the issue and resolution.

**Time: 12 minutes**


## Question 12: StatefulSet with Persistent Storage

Deploy a StatefulSet named `database-cluster` with:
1. 3 replicas
2. Each pod needs a persistent volume (PVC) of 10Gi
3. Pods should have stable DNS names like `database-cluster-0.database-cluster`, etc.
4. Service port 5432 should be exposed via a headless service

**Time: 10 minutes**


## Question 13: Resource Quotas and Limits

The `test` namespace is consuming too many resources. Implement:
1. ResourceQuota that limits the namespace to 4 CPU cores and 8Gi memory total
2. LimitRange that ensures individual pods request at least 100m CPU and 128Mi memory
3. Verify that a pod requesting 2 CPUs and 2Gi memory is rejected

**Time: 8 minutes**


## Question 14: Pod Security Standards

Namespace `restricted` needs to enforce security policies. Configure:
1. Pod Security Standards in `enforce` mode: `restricted`
2. Pod Security Standards in `audit` mode: `baseline`
3. Test by deploying a pod with `privileged: true` and verify it's denied

**Time: 8 minutes**


## Question 15: Multi-Container Pod with Sidecar

Create a pod named `app-with-logger` that:
1. Main container: runs `nginx` image
2. Sidecar container: runs `busybox` that tails nginx logs from a shared volume
3. Both containers share a volume at `/var/log/nginx` (for main) and `/logs` (for sidecar)
4. The pods should continue running and logging without errors

**Time: 8 minutes**

---

## End of Mock Exam 01

Total Time: 120 minutes

After completing, review your answers against the solutions provided in `MOCK-EXAM-01-SOLUTIONS.md`.
