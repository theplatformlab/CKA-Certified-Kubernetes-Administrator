# Mock Exam 02 — CKA Practice (Kubernetes 1.35)

Duration: 2 hours (120 minutes)
Questions: 16
Passing Score: 66% (weights in brackets; partial credit per check)

Start it with `./scripts/mock-exam.sh start 2`. That command builds two fresh clusters (`cka-exam` and `cka-exam-ops`), prepares every question, opens the question panel and a shell, and starts the docs-only browser. Each question tells you which context to use. Grade with `s` in the question panel or `./scripts/mock-exam.sh grade`.

Answer files go into `~/cka-exam/`. Node access: `ssh <node-name>`. In the exam shell this opens a root shell on the kind node.

Do not look at the solutions until you complete this exam.

---

## Question 1 — Service discovery and DNS (5%)

**Context:** `kubectl config use-context kind-cka-exam`

Namespace `frontend` contains a Service `web-ui` on port `3000`. An application in namespace `backend` needs to reach it.

1. Write the fully qualified DNS name of Service `web-ui` into `~/cka-exam/q01/dns.txt` (only the name).
2. Create a pod named `dns-test` in namespace `backend` with image `busybox:1.37` and command `sleep 3600`.
3. Use `dns-test` to resolve the Service's name with `nslookup`. Save the complete output to `~/cka-exam/q01/nslookup.txt`.


## Question 2 — Roll back a broken rollout (7%)

**Context:** `kubectl config use-context kind-cka-exam`

Deployment `payment-service` in namespace `payments` was updated several times. The latest update broke it.

1. Find the revision that introduced the broken version. Write its revision number into `~/cka-exam/q02/broken-revision.txt`.
2. Roll the Deployment back to the revision right before the broken one.
3. All 3 replicas must be Ready.


## Question 3 — Secrets as environment variables (6%)

**Context:** `kubectl config use-context kind-cka-exam`

In namespace `apps`:

1. Create a Secret named `db-credentials` with the keys `DB_USER=dbuser`, `DB_PASSWORD=secret123` and `DB_NAME=appdb`.
2. Create a Deployment named `db-client`:
   - 1 replica, image `busybox:1.37`, command `sleep 3600`
   - all three keys of the Secret available as environment variables with the same names
   - no secret values written into the Deployment manifest


## Question 4 — DaemonSet on all nodes (5%)

**Context:** `kubectl config use-context kind-cka-exam`

Create a DaemonSet named `node-agent` in namespace `monitoring`:

- pod label `app=node-agent`
- container `agent`, image `busybox:1.37`, command `sleep 86400`
- resource requests `10m` CPU and `16Mi` memory
- one pod on every node of the cluster, including the control plane node


## Question 5 — API server is down (9%)

**Context:** `kubectl config use-context kind-cka-exam-ops`

`kubectl` can no longer talk to cluster `cka-exam-ops`. The kube-apiserver runs as a static pod on `cka-exam-ops-control-plane` (`ssh cka-exam-ops-control-plane`).

Find the cause and fix it. The API server must be healthy again.


## Question 6 — ConfigMap changes and running pods (6%)

**Context:** `kubectl config use-context kind-cka-exam`

Deployment `config-app` in namespace `config-demo` uses ConfigMap `app-config`. It reads key `mode` as environment variable `APP_MODE`, and the ConfigMap is also mounted at `/etc/app`.

1. Change the ConfigMap: set `mode` to `production` and `message` to `v2`.
2. Make sure all pods of `config-app` use the new values, both in the environment variable and in the file `/etc/app/message`. Do not delete the Deployment.


## Question 7 — PriorityClasses (5%)

**Context:** `kubectl config use-context kind-cka-exam`

1. Create a PriorityClass named `critical-workload` with value `1000000` and description `critical`.
2. Create a PriorityClass named `standard-workload` with value `1000` and `preemptionPolicy: Never`.
   Neither PriorityClass may be the global default.
3. In namespace `priority`, create a Deployment `critical-app` with 2 replicas, image `busybox:1.37` and command `sleep 3600`, using PriorityClass `critical-workload`.
4. In namespace `priority`, create a pod `batch-job` with image `busybox:1.37` and command `sleep 3600`, using PriorityClass `standard-workload`.


## Question 8 — Expose an application with a NodePort (6%)

**Context:** `kubectl config use-context kind-cka-exam`

Deployment `legacy-app` in namespace `legacy` listens on port `3000`.

Create a Service named `legacy-svc` in namespace `legacy`:

- type `NodePort`
- Service port `8080`
- target port `3000`
- node port `30080`

The application must answer on `<any-node-ip>:30080`.


## Question 9 — CronJob (6%)

**Context:** `kubectl config use-context kind-cka-exam`

In namespace `backup`:

1. Create a CronJob named `db-backup`:
   - runs every day at 02:00
   - image `busybox:1.37`, command `sh -c 'echo backup done'`
   - keeps the last `3` successful and the last `1` failed Jobs
   - concurrency policy `Forbid`
   - suspended
2. Test it once right now: create a Job named `db-backup-manual` from the CronJob. The Job must complete successfully.


## Question 10 — Renew control plane certificates (8%)

**Context:** `kubectl config use-context kind-cka-exam-ops`

The certificates of cluster `cka-exam-ops` need to be renewed (`ssh cka-exam-ops-control-plane`).

1. Write the current expiration date of the kube-apiserver serving certificate into `~/cka-exam/q10/expiration.txt` on your exam host (not on the node). Use the same format `kubeadm certs check-expiration` prints, for example `Oct 28, 2027 21:12 UTC`.
2. Renew all certificates with kubeadm.
3. Make sure the running kube-apiserver serves the renewed certificate.


## Question 11 — PodDisruptionBudget (5%)

**Context:** `kubectl config use-context kind-cka-exam`

Deployment `frontend` in namespace `web` runs 10 replicas with pod label `app=frontend`.

Create a PodDisruptionBudget named `frontend-pdb` in namespace `web` that allows at most `2` of these pods to be unavailable during voluntary disruptions.


## Question 12 — Custom resources (5%)

**Context:** `kubectl config use-context kind-cka-exam`

The CRD `databases.example.com` (kind `Database`) is installed.

1. In namespace `team-data`, create a `Database` named `orders-db` with `engine: postgres`, `version: "17"` and `storageGB: 20`. Use `kubectl explain` to find the schema.
2. Delete the `Database` named `legacy-db` in namespace `team-data`.
3. Write the names of all CRDs in the API group `example.com` into `~/cka-exam/q12/crds.txt`, one per line.


## Question 13 — Pod Security Admission (6%)

**Context:** `kubectl config use-context kind-cka-exam`

1. Create namespace `secure-apps` with Pod Security Admission `enforce` and `warn` both set to level `restricted`.
2. Create a pod `restricted-pod` in `secure-apps` with image `nginxinc/nginx-unprivileged:1.28-alpine` that complies with the `restricted` level and is Running.
3. Try to create a pod `blocked-pod` in `secure-apps` with image `busybox:1.37`, command `sleep 3600` and `securityContext.privileged: true`. Save the error message to `~/cka-exam/q13/error.txt`.


## Question 14 — StorageClass and default class (8%)

**Context:** `kubectl config use-context kind-cka-exam`

1. Create a StorageClass named `local-ssd`:
   - provisioner `rancher.io/local-path`
   - `reclaimPolicy: Retain`
   - `volumeBindingMode: WaitForFirstConsumer`
2. Make `local-ssd` the cluster's default StorageClass. `standard` must no longer be the default.
3. In namespace `storage`, create a PVC named `data-pvc` that requests `2Gi` with `ReadWriteOnce`, without specifying a StorageClass.
4. In namespace `storage`, create a pod named `data-pod` with image `nginx:1.28` that mounts `data-pvc` at `/usr/share/nginx/html`. The PVC must be `Bound`.


## Question 15 — Namespace resource governance (6%)

**Context:** `kubectl config use-context kind-cka-exam`

In namespace `batch-jobs`:

1. Create a ResourceQuota named `batch-quota`:
   - `requests.cpu: 10`, `requests.memory: 20Gi`
   - `limits.cpu: 10`, `limits.memory: 20Gi`
   - `pods: 20`
2. Create a LimitRange named `batch-limits` for type `Container`:
   - minimum `500m` CPU and `256Mi` memory
   - maximum `4` CPU and `8Gi` memory
   - default request and default limit both `500m` CPU and `256Mi` memory

A container requesting `5` CPUs must then be rejected.


## Question 16 — Gateway API traffic splitting (7%)

**Context:** `kubectl config use-context kind-cka-exam`

The Gateway API CRDs and GatewayClass `exam-gateway` are installed. In namespace `gateway` the Services `web-v1` and `web-v2` (both port `80`) exist.

1. Create a Gateway named `web-gateway` in namespace `gateway`:
   - GatewayClass `exam-gateway`
   - one listener named `http`, protocol `HTTP`, port `80`, hostname `web.example.com`
2. Create an HTTPRoute named `web-route` in namespace `gateway`:
   - attached to `web-gateway`, hostname `web.example.com`
   - sends requests for path prefix `/` to `web-v1` (weight `80`) and `web-v2` (weight `20`), both on port `80`

---

## End of Mock Exam 02

Total Time: 120 minutes

After completing, review your answers against the solutions in `MOCK-EXAM-02-SOLUTIONS.md`.
