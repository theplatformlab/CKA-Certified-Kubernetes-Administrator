# CKS Study Plan

Resources, a 4-5 week plan and a checklist to track your progress per domain.

---

## Best CKS Study Resources 2026 — Free and Paid

In order of usefulness:

### Free

| Resource | Why |
|---|---|
| [Kubernetes Official Docs](https://kubernetes.io/docs/) | The only resource allowed during the exam. Get fast at searching it. |
| [Kubernetes Security Tasks](https://kubernetes.io/docs/tasks/administer-cluster/) | Step-by-step guides for audit logging, encryption at rest, etc. |
| [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/) | Must-bookmark. Allowed during the exam. |
| [CKS Curriculum PDF](https://github.com/cncf/curriculum) | The official syllabus. Check this before your exam. |
| [Killercoda CKS Scenarios](https://killercoda.com/cks) | Free hands-on labs in the browser. Good for daily practice. |
| [Falco Documentation](https://falco.org/docs/) | Learn Falco rules, conditions, output fields. |
| [Trivy Documentation](https://aquasecurity.github.io/trivy/) | Image scanning reference. |
| [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) | Know restricted/baseline/privileged levels inside out. |

### Paid

| Resource | Why | Cost |
|---|---|---|
| [killer.sh](https://killer.sh) | Included with exam purchase. 2 sessions, 24h each. Harder than the real exam. | Free with exam |
| [KodeKloud CKS Course](https://kodekloud.com) | Best structured CKS course. Labs are built-in. | ~$15-25/mo |
| [Udemy — CKS Course](https://www.udemy.com) | Multiple instructors available. Wait for Udemy sales ($10-15). | ~$15 |

### Local Practice Environments

| Tool | Notes |
|---|---|
| [kind](https://kind.sigs.k8s.io/) | Kubernetes in Docker. Fast to create/destroy clusters. My daily driver. |
| [minikube](https://minikube.sigs.k8s.io/) | Single-node cluster. Good for basic practice. |
| [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/) | Real cluster setup on VMs. Best for practicing CIS benchmarks and API server hardening. |

Advice: CKS is more hands-on than CKA. Spend 20% of your time on theory and 80% practicing with real tools (Falco, Trivy, kube-bench, AppArmor profiles).

---

## CKS Study Plan 2026 — How to Prepare in 4-5 Weeks

This assumes you already passed CKA. If your CKA knowledge is rusty, add an extra week to review RBAC, NetworkPolicy, and ServiceAccounts.

### Week 1 — Foundations + Cluster Setup

- Set up the lab's CKS cluster (`bash scripts/init-cluster.sh --profile cks`, see [docs/lab.md](../lab.md))
- Configure aliases and vim ([scripts/exam-setup.sh](../../scripts/exam-setup.sh))
- Cover Domain 1 (Cluster Setup): NetworkPolicy, CIS benchmarks, Ingress TLS
- Install and run kube-bench
- Practice this week's domains in the lab (the lab: `./cka`, Studying for: CKS)
- Practice writing NetworkPolicies from scratch — default deny + specific allow

### Week 2 — Hardening + System Security

- Cover Domain 2 (Cluster Hardening): RBAC, ServiceAccount security, API server hardening
- Cover Domain 3 (System Hardening): AppArmor, Seccomp profiles
- Practice this week's domains in the lab (the lab: `./cka`, Studying for: CKS)
- Practice RBAC imperative commands until they're muscle memory
- Load and apply AppArmor profiles on a node

### Week 3 — Microservice Vulnerabilities + Supply Chain

- Cover Domain 4 (Minimize Microservice Vulnerabilities): SecurityContext, Pod Security Admission, Secrets, encryption at rest, RuntimeClass
- Cover Domain 5 (Supply Chain Security): Trivy, Dockerfile best practices, registry restrictions
- Practice this week's domains in the lab (the lab: `./cka`, Studying for: CKS)
- Practice Trivy scanning and understand severity levels
- Set up encryption at rest at least twice

### Week 4 — Monitoring + Mock Exams

- Cover Domain 6 (Monitoring/Logging/Runtime Security): Falco, audit logging, runtime immutability
- Practice this week's domains in the lab (the lab: `./cka`, Studying for: CKS)
- Install Falco, trigger rules, write custom rules
- Configure audit logging end-to-end
- Do killer.sh session 1
- Take a lab mock exam (the lab: `./cka`, Studying for: CKS) under timed conditions (2 hours)

### Week 5 (Optional) — Polish

- Only if you didn't feel ready after Week 4
- Focus entirely on weak domains
- Redo the lab items you failed
- Do killer.sh session 2 (3 days before exam)
- Review the [mistakes list](exam-guide.md#mistakes-that-will-fail-you-on-the-cks) one more time

---

## CKS Study Progress Tracker

Track your progress across all CKS domains.

### Domain 1 — Cluster Setup (15%)

- [ ] Write NetworkPolicy from scratch (default deny + allow)
- [ ] AND vs OR in NetworkPolicy selectors
- [ ] Run kube-bench and fix findings
- [ ] Harden API server flags
- [ ] Harden kubelet configuration
- [ ] Create Ingress with TLS
- [ ] Block metadata endpoint with NetworkPolicy
- [ ] Verify binary checksums
- [ ] Practice this domain's items in the lab

### Domain 2 — Cluster Hardening (15%)

- [ ] RBAC: Role, ClusterRole, RoleBinding, ClusterRoleBinding
- [ ] Audit existing RBAC bindings
- [ ] Restrict API server access
- [ ] ServiceAccount security (disable auto-mount)
- [ ] Practice this domain's items in the lab

### Domain 3 — System Hardening (10%)

- [ ] AppArmor — load profiles, apply to pods (GA field, not annotation)
- [ ] Seccomp — RuntimeDefault and Localhost profiles
- [ ] Minimize host OS attack surface
- [ ] Practice this domain's items in the lab

### Domain 4 — Minimize Microservice Vulnerabilities (20%)

- [ ] SecurityContext — full hardened pattern memorized
- [ ] Pod Security Admission — enforce/audit/warn + levels
- [ ] Secrets — create, use, encrypt at rest
- [ ] EncryptionConfiguration — aescbc setup
- [ ] RuntimeClass — gVisor/Kata concept
- [ ] ValidatingAdmissionPolicy — CEL expressions
- [ ] Practice this domain's items in the lab

### Domain 5 — Supply Chain Security (20%)

- [ ] Trivy — image scanning, severity filtering
- [ ] Dockerfile best practices (multi-stage, non-root, minimal base)
- [ ] Registry restrictions (allowlisting)
- [ ] Image digest vs tag
- [ ] Static analysis tools (kubesec, conftest)
- [ ] Practice this domain's items in the lab

### Domain 6 — Monitoring, Logging and Runtime Security (20%)

- [ ] Audit logging — policy levels, API server config, volume mounts
- [ ] Falco — install, rules, alerts, custom rules
- [ ] Runtime immutability — readOnlyRootFilesystem + emptyDir
- [ ] Behavioral analytics — identify suspicious activity
- [ ] Container investigation with crictl
- [ ] Practice this domain's items in the lab

### Exam Readiness

- [ ] Aliases and vim config memorized
- [ ] Can write NetworkPolicy from memory
- [ ] Can write SecurityContext hardening from memory
- [ ] killer.sh session 1 completed
- [ ] killer.sh session 2 completed
- [ ] Mock exam completed (>67%)
- [ ] ID verified and CNCF account name matches
