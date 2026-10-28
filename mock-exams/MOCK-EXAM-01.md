# Mock Exam 01 — CKA Practice (Kubernetes 1.35)

Duration: 2 hours (120 minutes)
Questions: 15
Passing Score: 66% (weights in brackets; partial credit per check)

Start it with `./scripts/mock-exam.sh start 1`. That command builds two fresh clusters (`cka-exam` and `cka-exam-ops`), prepares every question, opens the question panel and a shell, and starts the docs-only browser. Each question tells you which context to use. Grade with `s` in the question panel or `./scripts/mock-exam.sh grade`.

Answer files go into `~/cka-exam/`. Node access: `ssh <node-name>`. In the exam shell this opens a root shell on the kind node.

Do not look at the solutions until you complete this exam.

---

## Question 1 — Fix a crashing pod with a ConfigMap (6%)

**Context:** `kubectl config use-context kind-cka-exam`

Pod `app-frontend` in namespace `production` is in `CrashLoopBackOff`. It expects a configuration file at `/etc/app/config.yaml`, but the file does not exist. The pod's manifest is saved at `~/cka-exam/q01/app-frontend.yaml`.

1. Create a ConfigMap named `app-config` in namespace `production` with one key, `config.yaml`, whose content is exactly:
   `database_host: postgres.production.svc.cluster.local`
2. Make the ConfigMap available to pod `app-frontend` so that the file `/etc/app/config.yaml` contains that content.
3. The pod must keep its name, image and command, and must be `Running`.


## Question 2 — RBAC for a user and a ServiceAccount (6%)

**Context:** `kubectl config use-context kind-cka-exam`

In namespace `staging`:

1. Create a Role named `dev-reader` that allows `get`, `list` and `watch` on Pods and Deployments, and nothing else.
2. Create a ServiceAccount named `ci-bot`.
3. Create a RoleBinding named `dev-reader-binding` that grants the Role to the user `dev-user` and to the ServiceAccount `ci-bot`.

`dev-user` must not get any permissions outside namespace `staging`.


## Question 3 — Node maintenance (6%)

**Context:** `kubectl config use-context kind-cka-exam`

Node `cka-exam-worker2` needs maintenance.

1. Make the node unschedulable and evict all workloads from it. Only DaemonSet-managed pods may remain on the node.
2. Deployment `shop-api` in namespace `maintenance` must end up with all 3 replicas Ready on other nodes.
3. The standalone pod `scratch` in namespace `maintenance` stores only temporary data. Losing it is acceptable.

Leave the node unschedulable.


## Question 4 — Static PersistentVolume (7%)

**Context:** `kubectl config use-context kind-cka-exam`

The Deployment `db-app` in namespace `databases` needs shared storage.

1. Create a StorageClass named `fast-ssd` with provisioner `kubernetes.io/no-provisioner`, `volumeBindingMode: WaitForFirstConsumer` and `reclaimPolicy: Retain`.
2. Create a PersistentVolume named `db-pv`:
   - capacity `5Gi`
   - access mode `ReadWriteMany`
   - StorageClass `fast-ssd`
   - reclaim policy `Retain`
   - `hostPath` `/mnt/data/db`, type `DirectoryOrCreate`
3. Create a PersistentVolumeClaim named `db-pvc` in namespace `databases`. It must request `5Gi` with `ReadWriteMany` from StorageClass `fast-ssd`.
4. Update Deployment `db-app` to mount the claim at `/data`. The Deployment must be Ready and the PVC `Bound` to `db-pv`.


## Question 5 — NetworkPolicies for a three-tier app (8%)

**Context:** `kubectl config use-context kind-cka-exam`

Namespace `shop` runs three Deployments, `frontend`, `backend` and `database`, with pod labels `tier=frontend`, `tier=backend` and `tier=database`. Each tier has a Service with the same name. Currently all traffic is allowed.

Create NetworkPolicies in namespace `shop` so that:

1. Pods with `tier=frontend` accept ingress on TCP port `80` from anywhere, including other namespaces.
2. Pods with `tier=backend` accept ingress only from `tier=frontend` pods in `shop`, on TCP port `3000`.
3. Pods with `tier=database` accept ingress only from `tier=backend` pods in `shop`, on TCP port `5432`.
4. All other ingress traffic to pods in `shop` is denied. Do not restrict egress.


## Question 6 — Install a local Helm chart (7%)

**Context:** `kubectl config use-context kind-cka-exam`

A Helm chart is located at `~/cka-exam/helm-charts/monitoring`.

Install it as release `monitoring-stack` in namespace `monitoring` and create the namespace if needed. Override these chart values:

- `replicaCount` = `3`
- `persistence.enabled` = `true`
- `persistence.size` = `2Gi`

Do not modify the chart files. All replicas must be Ready.


## Question 7 — Kubelet and container runtime (8%)

**Context:** `kubectl config use-context kind-cka-exam-ops`

Node `cka-exam-ops-worker` is `NotReady`. Access it with `ssh cka-exam-ops-worker`.

Fix the node so that it is `Ready` again. The kubelet must use containerd at `unix:///run/containerd/containerd.sock`, and it must be enabled to start automatically when the node boots.


## Question 8 — API server audit logging (7%)

**Context:** `kubectl config use-context kind-cka-exam-ops`

Enable audit logging on the kube-apiserver of node `cka-exam-ops-control-plane` (`ssh cka-exam-ops-control-plane`).

1. Create the audit policy `/etc/kubernetes/audit/policy.yaml` with these rules:
   - Secrets in all namespaces are logged at level `Metadata`.
   - ConfigMaps in namespace `default` are logged at level `Request`.
   - Nothing else is logged.
2. Configure the kube-apiserver to:
   - use that policy file
   - write the log to `/var/log/kubernetes/audit/audit.log`
   - keep logs for at most `7` days
   - keep at most `3` old log files
3. The kube-apiserver must be running again afterwards.


## Question 9 — HorizontalPodAutoscaler (5%)

**Context:** `kubectl config use-context kind-cka-exam`

Deployment `web-app` in namespace `production` runs with 2 replicas.

Create a HorizontalPodAutoscaler (`autoscaling/v2`) named `web-app` in namespace `production` that:

- targets Deployment `web-app`
- keeps the average CPU utilization at `70%`
- scales between `2` and `10` replicas
- uses a scale-down stabilization window of `30` seconds


## Question 10 — Ingress with TLS (6%)

**Context:** `kubectl config use-context kind-cka-exam`

In namespace `api`, a Service `api` listens on port `8080`. The TLS Secret `api-tls-cert` and the IngressClass `nginx` already exist.

Create an Ingress named `api-ingress` in namespace `api`:

- IngressClass `nginx`
- TLS for host `api.example.com` using Secret `api-tls-cert`
- host `api.example.com` with two paths, both going to Service `api` on port `8080`:
  - `/api`, path type `Prefix`
  - `/health`, path type `Exact`


## Question 11 — Pods stuck in Pending (8%)

**Context:** `kubectl config use-context kind-cka-exam-ops`

The pods of Deployment `rescue` in namespace `default` stay `Pending`.

Find the cause and fix it so that all replicas run. Do not modify the Deployment.


## Question 12 — StatefulSet with stable storage (7%)

**Context:** `kubectl config use-context kind-cka-exam`

In namespace `databases`:

1. Create a headless Service named `database-cluster`:
   - selector `app=database-cluster`
   - port `5432`, named `postgres`
2. Create a StatefulSet named `database-cluster`:
   - 3 replicas, governed by the Service above, pod label `app=database-cluster`
   - one container named `postgres`, image `postgres:17-alpine`, container port `5432`
   - environment `POSTGRES_PASSWORD=exam-pass` and `PGDATA=/var/lib/postgresql/data/pgdata`
   - a volume claim template named `data`: `ReadWriteOnce`, `1Gi`, default StorageClass, mounted at `/var/lib/postgresql/data`

All 3 pods must be Ready. They must be resolvable as `database-cluster-0.database-cluster.databases.svc.cluster.local` and so on.


## Question 13 — ResourceQuota and LimitRange (6%)

**Context:** `kubectl config use-context kind-cka-exam`

Namespace `test` uses too many resources. In namespace `test`:

1. Create a ResourceQuota named `compute-quota` with these limits:
   - `requests.cpu: 4`
   - `requests.memory: 8Gi`
   - `limits.cpu: 4`
   - `limits.memory: 8Gi`
2. Create a LimitRange named `container-limits` for type `Container`:
   - default request: `100m` CPU, `128Mi` memory
   - default limit: `200m` CPU, `256Mi` memory
   - minimum: `100m` CPU, `128Mi` memory
   - maximum: `1` CPU, `1Gi` memory

Afterwards, a pod whose container requests `2` CPUs and `2Gi` memory must be rejected. A pod without any resources must be admitted with the defaults.


## Question 14 — Pod Security Standards (7%)

**Context:** `kubectl config use-context kind-cka-exam`

Namespace `restricted` runs Deployment `web`.

1. Configure Pod Security Admission on namespace `restricted`:
   - `enforce` at level `restricted`
   - `warn` at level `restricted`
   - `audit` at level `baseline`
2. Update Deployment `web` so that its pods are admitted under the `restricted` level, and make sure all its replicas are Running. Do not change the image.

Privileged pods must then be rejected in this namespace.


## Question 15 — Native sidecar container (6%)

**Context:** `kubectl config use-context kind-cka-exam`

Create a pod named `app-with-logger` in namespace `logging`:

- main container `nginx`, image `nginx:1.28`, which mounts an `emptyDir` volume named `logs` at `/var/log/nginx`
- a sidecar named `logger`, image `busybox:1.37`, implemented as a native sidecar (an init container that keeps running), with command `sh -c 'tail -F /logs/access.log'` and the same `logs` volume mounted at `/logs`

Requests to nginx must show up in the logs of container `logger`.

---

## End of Mock Exam 01

Total Time: 120 minutes

After completing, review your answers against the solutions in `MOCK-EXAM-01-SOLUTIONS.md`.
