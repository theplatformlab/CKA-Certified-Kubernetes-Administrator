# CKS Syllabus

The six domains of the CKS curriculum with the concepts, commands and manifests for each.

---

## What Changed in Kubernetes v1.34 for CKS

If you're studying from a guide written for v1.29 or v1.30, some of it is wrong. Here's what changed that matters for the CKS:

| Feature | Status in v1.34 | CKS Impact |
|---|---|---|
| **AppArmor support** | GA | AppArmor profiles use `securityContext.appArmorProfile` field (not annotations). |
| **ValidatingAdmissionPolicy** | GA | CEL-based admission without webhooks. Replaces some OPA Gatekeeper use cases. Know the syntax. |
| **Pod Security Admission** | GA (since v1.25) | Replaces PodSecurityPolicy entirely. Know enforce/audit/warn modes + restricted/baseline/privileged levels. |
| **Seccomp default** | GA | RuntimeDefault seccomp profile is the standard. Know Localhost profiles too. |
| **Sidecar containers (native)** | GA | Init containers with `restartPolicy: Always`. Relevant for security sidecars (log forwarding, proxies). |
| **User namespaces** | Beta | Pods can run in isolated user namespaces. Know the concept — probably not tested yet. |
| **kubectl debug** | GA | `k debug node/<name>` and `k debug pod/<name>` — useful for security investigation tasks. |
| **Image volume source** | Beta | Mount OCI images as volumes. Know it exists for supply chain context. |

The big ones for CKS prep: AppArmor GA (field-based, not annotation-based), ValidatingAdmissionPolicy, and Pod Security Admission. If your study material still references PodSecurityPolicy, it's outdated — PSP was removed in v1.25.

---

## CKS Syllabus Breakdown (v1.34)

### Domain 1 — Cluster Setup (15%)

15% of the score. This is about securing the cluster infrastructure itself — network policies, CIS benchmarks, Ingress TLS, and GUI security.

#### 1.1 — Use Network Security Policies to Restrict Cluster Level Access

NetworkPolicy is your primary tool for pod-to-pod traffic control. Once you apply any NetworkPolicy to a pod, all traffic not explicitly allowed is denied for that pod.

```yaml
# Default deny all — apply first, then open specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

```yaml
# Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  # Always allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
```

Critical gotcha: if you add an Egress policy, you must also allow DNS (UDP 53). Otherwise the pod can't resolve service names and everything looks broken even though the policy is "correct."

Another gotcha: `from` with multiple selectors in one rule = AND. Multiple rules = OR.

```yaml
# AND — must match BOTH namespace AND pod label
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: prod
    podSelector:
      matchLabels:
        app: frontend

# OR — matches namespace OR pod label
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: prod
- from:
  - podSelector:
      matchLabels:
        app: frontend
```

This difference is easy to miss. Read the indentation carefully.

#### 1.2 — Use CIS Benchmark to Review the Security Configuration of Kubernetes Components

CIS benchmarks are security best practices published by the Center for Internet Security. **kube-bench** is the tool that checks your cluster against these benchmarks.

```bash
# Run kube-bench
kube-bench run --targets=master
kube-bench run --targets=node
kube-bench run --targets=etcd

# Check specific section
kube-bench run --targets=master --check=1.2.16

# Common findings to fix
# 1.2.16 — Ensure admission control plugin PodSecurityPolicy/PodSecurity is set
# 1.2.18 — Ensure audit logging is enabled
# 4.2.1 — Ensure kubelet anonymous auth is disabled
```

Common API server hardening flags:
```bash
# In /etc/kubernetes/manifests/kube-apiserver.yaml
--anonymous-auth=false
--authorization-mode=Node,RBAC
--enable-admission-plugins=NodeRestriction
--audit-log-path=/var/log/kubernetes/audit/audit.log
--audit-policy-file=/etc/kubernetes/audit/policy.yaml
--profiling=false
--insecure-port=0
```

Kubelet hardening (`/var/lib/kubelet/config.yaml`):
```yaml
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
authorization:
  mode: Webhook
readOnlyPort: 0
protectKernelDefaults: true
```

After changing kubelet config: `sudo systemctl restart kubelet`

#### 1.3 — Properly Set Up Ingress with TLS

Every Ingress on the exam should use TLS. The pattern:

```bash
# Generate self-signed cert (exam might pre-create these)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=app.example.com"

# Create TLS secret
k create secret tls tls-secret --cert=tls.crt --key=tls.key -n <namespace>
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.example.com
    secretName: tls-secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

#### 1.4 — Protect Node Metadata and Endpoints

Cloud providers expose metadata APIs (e.g., `http://169.254.169.254`). Pods shouldn't be able to reach these. Use a NetworkPolicy to block metadata access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-metadata
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # Allow everything except metadata IP
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32
```

#### 1.5 — Minimize Use of, and Access to, GUI Elements

Kubernetes Dashboard and similar GUIs are attack surfaces. On the exam:
- Don't install the Dashboard unless asked
- If it's running, verify it uses RBAC (not admin-level ServiceAccount)
- Check that Dashboard ServiceAccount has minimal permissions
- Ensure Dashboard is only accessible behind authentication

```bash
# Check if Dashboard is running
k get pods -n kubernetes-dashboard
k get svc -n kubernetes-dashboard

# Check Dashboard ServiceAccount permissions
k get clusterrolebinding -o wide | grep dashboard
```

#### 1.6 — Verify Platform Binaries Before Deploying

Verify downloaded binaries using SHA checksums:

```bash
# Download kubectl and verify checksum
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
# Should output: kubectl: OK
```

---

### Domain 2 — Cluster Hardening (15%)

15% of the score. This covers RBAC, ServiceAccount security, and keeping Kubernetes updated.

#### 2.1 — Restrict Access to Kubernetes API

Control who and what can talk to the API server:

```bash
# Check anonymous access
curl -k https://localhost:6443/api/v1/pods
# Should be forbidden if anonymous auth is disabled

# API server flags to check
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -E "anonymous-auth|authorization-mode|enable-admission"
```

Key practices:
- `--anonymous-auth=false`
- `--authorization-mode=Node,RBAC` (never `AlwaysAllow`)
- `--enable-admission-plugins=NodeRestriction`
- Use certificates for API authentication, not tokens with long lifetimes
- Restrict API server network access (firewall rules, NetworkPolicy)

#### 2.2 — Use RBAC to Minimize Exposure

Least-privilege RBAC is critical. Never give more permissions than needed.

```bash
# Create Role (namespace-scoped)
k create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  -n dev

# Create RoleBinding
k create rolebinding read-pods \
  --role=pod-reader \
  --serviceaccount=dev:my-sa \
  -n dev

# Check permissions
k auth can-i list pods -n dev --as=system:serviceaccount:dev:my-sa
k auth can-i delete pods -n dev --as=system:serviceaccount:dev:my-sa
```

Audit existing permissions to find over-privileged accounts:

```bash
# Who has cluster-admin?
k get clusterrolebinding -o wide | grep cluster-admin

# What can a specific SA do?
k auth can-i --list --as=system:serviceaccount:default:default

# Check for dangerous permissions
k auth can-i create pods --as=system:serviceaccount:default:default
k auth can-i get secrets --as=system:serviceaccount:default:default
```

A ClusterRole bound with a RoleBinding only grants access in that namespace. A ClusterRole bound with a ClusterRoleBinding grants access cluster-wide. Same ClusterRole, different scope depending on the binding type.

#### 2.3 — Exercise Caution in Using Service Accounts

Default ServiceAccounts get auto-mounted tokens. This is a security risk.

```yaml
# Disable auto-mount on ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secure-sa
  namespace: default
automountServiceAccountToken: false
```

```yaml
# Or disable on the Pod level
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  serviceAccountName: secure-sa
  automountServiceAccountToken: false
  containers:
  - name: app
    image: nginx:1.27
```

Best practices:
- Don't use the `default` ServiceAccount for workloads — create dedicated SAs
- Set `automountServiceAccountToken: false` unless the pod actually needs API access
- Use short-lived tokens with TokenRequest API instead of long-lived secrets
- Audit which ServiceAccounts have cluster-admin or elevated permissions

```bash
# Check if default SA has elevated bindings
k get rolebinding,clusterrolebinding --all-namespaces -o wide | grep default

# Patch default SA to disable auto-mount
k patch sa default -n <namespace> -p '{"automountServiceAccountToken": false}'
```

#### 2.4 — Restrict Access to Kubernetes Dashboard

Same as 1.5 — ensure Dashboard uses RBAC with minimal permissions. Don't expose it publicly without authentication. If the exam says "restrict Dashboard access," ensure the ServiceAccount bound to Dashboard only has view-level permissions, not cluster-admin.

#### 2.5 — Update Kubernetes Frequently

Keep clusters updated to get security patches. Know the kubeadm upgrade sequence from your CKA prep. On CKS, the focus is knowing WHY you upgrade (CVEs, security fixes) rather than the mechanics.

---

### Domain 3 — System Hardening (10%)

10% of the score. This covers OS-level security — AppArmor, Seccomp, reducing attack surface, and network security at the host level.

#### 3.1 — Minimize Host OS Footprint

Reduce the attack surface of worker nodes:
- Remove unnecessary packages and services
- Disable unused kernel modules
- Use minimal base OS images (Ubuntu Server minimal, not desktop)
- Keep the OS updated

```bash
# List running services
systemctl list-units --type=service --state=running

# Disable unnecessary services
sudo systemctl disable --now <service-name>

# Check open ports
sudo ss -tlnp
sudo netstat -tlnp
```

#### 3.2 — Minimize IAM Roles

If running on a cloud provider:
- Use node-level IAM roles with minimal permissions
- Don't give nodes access to secrets management or admin APIs
- Use workload identity (GKE) or IRSA (EKS) instead of node-level roles
- Audit IAM roles attached to worker nodes

#### 3.3 — Minimize External Access to the Network

```bash
# Check externally exposed services
k get svc --all-namespaces | grep -E "NodePort|LoadBalancer"

# Services should be ClusterIP unless they need external access
# Convert NodePort to ClusterIP if not needed
k patch svc <service> -p '{"spec":{"type":"ClusterIP"}}'
```

#### 3.4 — Appropriately Use Kernel Hardening Tools (AppArmor, Seccomp)

**AppArmor** restricts what a process can do at the OS level (file access, network, capabilities). GA since v1.30 — uses the `securityContext` field, not annotations.

```bash
# Check AppArmor status on node
sudo aa-status
sudo apparmor_status

# Load a profile
sudo apparmor_parser -q /etc/apparmor.d/my-profile

# Check what profiles are loaded
sudo aa-status | grep profiles
```

```yaml
# Pod with AppArmor — GA field (not annotation)
apiVersion: v1
kind: Pod
metadata:
  name: apparmor-pod
spec:
  containers:
  - name: app
    image: nginx:1.27
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: my-custom-profile
```

AppArmor profile types:
- `RuntimeDefault` — uses the container runtime's default profile
- `Localhost` — uses a profile loaded on the node
- `Unconfined` — no AppArmor restrictions (avoid this)

**Seccomp** restricts which system calls a container can make.

```yaml
# Pod with Seccomp
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-pod
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:1.27
```

```yaml
# Localhost Seccomp profile
# Profile file at: /var/lib/kubelet/seccomp/profiles/my-profile.json
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/my-profile.json
```

Seccomp profile types:
- `RuntimeDefault` — container runtime default (recommended baseline)
- `Localhost` — custom profile on the node
- `Unconfined` — no seccomp filtering (avoid this)

On the exam: know how to apply both AppArmor and Seccomp to a pod. The most common task is setting `RuntimeDefault` or applying a `Localhost` profile that's already loaded on the node.

---

### Domain 4 — Minimize Microservice Vulnerabilities (20%)

20% of the score. This covers SecurityContext, Pod Security Standards, OPA/Gatekeeper, Secrets, and runtime sandboxes.

#### 4.1 — Set Up Appropriate OS-Level Security Domains (SecurityContext)

SecurityContext is the primary way to harden pods. Memorize this pattern:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:1.27
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache/nginx
    - name: run
      mountPath: /var/run
  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
  - name: run
    emptyDir: {}
```

Key fields:
- `runAsNonRoot: true` — container must run as non-root
- `readOnlyRootFilesystem: true` — makes the root filesystem immutable
- `allowPrivilegeEscalation: false` — prevents gaining more privileges than parent
- `capabilities.drop: [ALL]` — drops all Linux capabilities
- `seccompProfile.type: RuntimeDefault` — applies default seccomp filtering

When `readOnlyRootFilesystem` is true, the container can't write anywhere except explicitly mounted writable volumes (emptyDir, PVC, etc.).

#### 4.2 — Manage Kubernetes Secrets

Secrets are base64-encoded by default, NOT encrypted. To secure them properly:

**Create and use secrets:**

```bash
# Create
k create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=s3cret

# View (decoded)
k get secret db-creds -o jsonpath='{.data.password}' | base64 -d
```

```yaml
# As environment variables
env:
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: db-creds
      key: username

# As volume mount (more secure — files, not env vars)
volumeMounts:
- name: secret-vol
  mountPath: /etc/db-creds
  readOnly: true
volumes:
- name: secret-vol
  secret:
    secretName: db-creds
```

**Encrypt secrets at rest:**

```yaml
# /etc/kubernetes/enc/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}
```

```bash
# Generate encryption key
head -c 32 /dev/urandom | base64

# Add to kube-apiserver manifest
# --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
# Add volume mount for /etc/kubernetes/enc/

# After enabling, re-encrypt all existing secrets
k get secrets --all-namespaces -o json | k replace -f -
```

Order matters in EncryptionConfiguration: the first provider is used for encryption, all providers are tried for decryption. Put `identity: {}` last as a fallback to read unencrypted secrets.

#### 4.3 — Use Container Runtime Sandboxes (gVisor, Kata Containers)

Runtime sandboxes add an extra isolation layer between containers and the host kernel.

```yaml
# RuntimeClass for gVisor
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

```yaml
# Pod using sandboxed runtime
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed
spec:
  runtimeClassName: gvisor
  containers:
  - name: app
    image: nginx:1.27
```

Know the concept: gVisor intercepts system calls with a user-space kernel. Kata Containers uses lightweight VMs. Both provide stronger isolation than standard containerd/runc.

#### 4.4 — Implement Pod-to-Pod Encryption (mTLS)

Service meshes like Istio and Linkerd provide automatic mTLS between pods. On the CKS exam, you're more likely to be asked about the concept than to implement a full service mesh. Know that:

- mTLS encrypts traffic between pods
- Service meshes inject sidecar proxies to handle encryption
- Without mTLS, pod-to-pod traffic is unencrypted by default
- NetworkPolicy controls where traffic can go; mTLS secures the traffic itself

#### 4.5 — Use Pod Security Admission

Pod Security Admission (PSA) replaced PodSecurityPolicy (removed in v1.25). It uses namespace labels to enforce security standards.

Three levels:
- `privileged` — no restrictions (unrestricted)
- `baseline` — prevents known privilege escalation
- `restricted` — heavily locked down (best practice)

Three modes:
- `enforce` — reject pods that violate
- `audit` — log violations but allow
- `warn` — warn user but allow

```yaml
# Apply to a namespace
apiVersion: v1
kind: Namespace
metadata:
  name: secure-ns
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.34
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

```bash
# Apply via kubectl
k label ns secure-ns pod-security.kubernetes.io/enforce=restricted
k label ns secure-ns pod-security.kubernetes.io/audit=restricted
k label ns secure-ns pod-security.kubernetes.io/warn=restricted
```

A pod that violates the `restricted` level (e.g., runs as root, allows privilege escalation) will be rejected if the namespace has `enforce: restricted`.

#### 4.6 — Use OPA Gatekeeper / ValidatingAdmissionPolicy

**ValidatingAdmissionPolicy** (GA in v1.30+) uses CEL expressions for admission control without external webhooks:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-non-root
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: "object.spec.containers.all(c, has(c.securityContext) && has(c.securityContext.runAsNonRoot) && c.securityContext.runAsNonRoot == true)"
    message: "All containers must set runAsNonRoot to true"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-non-root-binding
spec:
  policyName: require-non-root
  validationActions:
  - Deny
  matchResources:
    namespaceSelector:
      matchLabels:
        env: production
```

**OPA Gatekeeper** uses ConstraintTemplates and Constraints. On the CKS, you may need to create or modify constraints but probably won't need to write Rego from scratch.

---

### Domain 5 — Supply Chain Security (20%)

20% of the score. This covers image security, image scanning, Dockerfile best practices, and allowlisting registries.

#### 5.1 — Minimize Base Image Footprint

Use minimal images to reduce attack surface:

```dockerfile
# Bad — full OS image with unnecessary tools
FROM ubuntu:22.04

# Better — Alpine-based
FROM python:3.12-alpine

# Best — distroless (no shell, no package manager)
FROM gcr.io/distroless/python3-debian12
```

Docker best practices:
- Use multi-stage builds to separate build dependencies from runtime
- Use specific image tags (never `:latest`)
- Don't install unnecessary packages
- Don't copy secrets into the image
- Use non-root USER
- Use `.dockerignore` to exclude `.git`, `*.env`, `*.key`

```dockerfile
# Multi-stage build example
FROM python:3.12-alpine AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt

FROM python:3.12-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/deps /app/deps
COPY . .
USER appuser
EXPOSE 8080
ENTRYPOINT ["python", "app.py"]
```

#### 5.2 — Secure Your Supply Chain (Allowlist Registries, Sign Images)

Restrict which image registries can be used in your cluster:

```yaml
# ValidatingAdmissionPolicy to restrict registries
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: restrict-registries
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: "object.spec.containers.all(c, c.image.startsWith('myregistry.io/') || c.image.startsWith('docker.io/library/'))"
    message: "Images must come from approved registries"
```

Or use OPA Gatekeeper / ImagePolicyWebhook to enforce registry restrictions.

Key concepts:
- Image signing with cosign/Notary — verify images before deployment
- Use image digests (`@sha256:...`) instead of tags for immutable references
- Private registries with authentication (imagePullSecrets)
- Scan images before they enter the cluster

#### 5.3 — Use Static Analysis of User Workloads (Kubesec, Conftest)

Static analysis tools check Kubernetes YAML for security issues before deployment:

```bash
# Kubesec — scan a pod manifest
kubesec scan pod.yaml

# Conftest — policy-as-code using OPA/Rego
conftest test pod.yaml

# Trivy can also scan config files
trivy config .
trivy config Dockerfile
```

#### 5.4 — Scan Images for Known Vulnerabilities (Trivy)

Trivy is the image scanner you'll use on the CKS:

```bash
# Scan an image
trivy image nginx:1.27

# Filter by severity
trivy image --severity CRITICAL,HIGH nginx:1.27

# Only CRITICAL
trivy image --severity CRITICAL nginx:1.27 --quiet

# Compare images (Alpine vs full)
trivy image nginx:1.27          # Many vulnerabilities
trivy image nginx:1.27-alpine   # Fewer vulnerabilities

# Scan and output to file
trivy image --severity CRITICAL nginx:1.27 -o results.txt

# Scan a Dockerfile
trivy config Dockerfile
```

On the exam: you might be asked to scan an image, identify CRITICAL vulnerabilities, and then use a different (safer) image. Or you might need to write a policy that blocks images with CRITICAL vulns.

---

### Domain 6 — Monitoring, Logging and Runtime Security (20%)

20% of the score. This covers audit logging, Falco, runtime detection, and ensuring containers are immutable.

#### 6.1 — Perform Behavioral Analytics to Detect Malicious Activities

Know how to identify suspicious activity in a cluster:
- Unexpected processes running in containers (shells, curl, wget)
- Containers accessing sensitive files (`/etc/shadow`, `/etc/passwd`)
- Unexpected network connections
- Privilege escalation attempts
- Container breakout attempts

Tools: Falco is the primary tool for this on the CKS.

#### 6.2 — Perform Deep Analytical Investigation and Identification of Bad Actors

```bash
# Check recent events
k get events --sort-by='.lastTimestamp' -A

# Check who did what (audit logs)
cat /var/log/kubernetes/audit/audit.log | jq 'select(.user.username=="suspect-user")'

# Check container processes
k exec <pod> -- ps aux
k exec <pod> -- cat /proc/1/cmdline

# Check network connections from a pod
k exec <pod> -- netstat -tlnp
k exec <pod> -- ss -tlnp

# Use crictl to inspect containers on a node
sudo crictl ps
sudo crictl inspect <container-id>
sudo crictl logs <container-id>
```

#### 6.3 — Ensure Immutability of Containers at Runtime

Immutable containers can't be modified after deployment. This prevents attackers from installing tools or modifying binaries.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: immutable-pod
spec:
  containers:
  - name: app
    image: nginx:1.27
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      runAsNonRoot: true
      runAsUser: 1000
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache/nginx
    - name: run
      mountPath: /var/run
  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
  - name: run
    emptyDir: {}
```

Key immutability controls:
- `readOnlyRootFilesystem: true` — container can't write to filesystem
- `allowPrivilegeEscalation: false` — can't gain more privileges
- `capabilities.drop: [ALL]` — no Linux capabilities
- Use emptyDir for paths that genuinely need to be writable (/tmp, /var/cache, /var/run)
- Use distroless or read-only base images

#### 6.4 — Use Audit Logs to Monitor Access

Kubernetes audit logging records all API requests. Configure it in the API server.

**Audit policy:**

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Don't log events
- level: None
  resources:
  - group: ""
    resources: ["events"]

# Log secret access at Metadata level
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]

# Log pod changes at RequestResponse level
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods"]

# Catch-all at Metadata level
- level: Metadata
  omitStages:
  - RequestReceived
```

Audit levels:
- `None` — don't log
- `Metadata` — log request metadata (user, timestamp, resource, verb) but not body
- `Request` — log metadata + request body
- `RequestResponse` — log metadata + request body + response body

**API server configuration:**

```yaml
# In /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
    volumeMounts:
    - name: audit-policy
      mountPath: /etc/kubernetes/audit
      readOnly: true
    - name: audit-log
      mountPath: /var/log/kubernetes/audit
  volumes:
  - name: audit-policy
    hostPath:
      path: /etc/kubernetes/audit
      type: DirectoryOrCreate
  - name: audit-log
    hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
```

After changing the API server manifest, wait for the static pod to restart. `kubectl` may be unresponsive for 30-60 seconds — that's normal.

#### 6.5 — Use Falco to Detect Threats at Runtime

Falco monitors system calls and fires alerts when suspicious activity is detected.

```bash
# Install Falco (if not already installed)
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" | sudo tee /etc/apt/sources.list.d/falcosecurity.list
sudo apt-get update && sudo apt-get install -y falco
sudo systemctl start falco
```

**Built-in rules trigger on:**
- Shell spawned in container
- Read of sensitive files (`/etc/shadow`)
- Write below known directories
- Namespace change (setns)
- Unexpected process started

**Custom Falco rule:**

```yaml
# /etc/falco/rules.d/custom-rules.yaml
- rule: Detect curl or wget in container
  desc: Detects download tools in containers
  condition: >
    spawned_process and
    container and
    (proc.name in (curl, wget))
  output: >
    curl/wget detected in container
    (user=%user.name command=%proc.cmdline container_id=%container.id
    container_name=%container.name image=%container.image.repository
    namespace=%k8s.ns.name pod=%k8s.pod.name)
  priority: WARNING
  tags: [network, process, mitre_exfiltration]
```

```bash
# Restart Falco after adding rules
sudo systemctl restart falco

# Test — run curl inside a container
k exec -it <pod> -- curl example.com

# Check alerts
journalctl -u falco --no-pager | tail -20
cat /var/log/syslog | grep falco
```

On the exam, you might need to:
- Install Falco and start it
- Find which rule triggered an alert
- Write a custom rule to detect specific behavior
- Read Falco output to identify what happened
