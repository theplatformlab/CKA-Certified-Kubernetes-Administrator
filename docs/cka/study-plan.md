# CKA Study Plan

Resources, a 4-5 week plan and a checklist to track your progress per domain.

---

## Study Resources for CKA 2026

In order of usefulness:

### Free

| Resource | What it is good for |
|---|---|
| [Kubernetes Official Docs](https://kubernetes.io/docs/) | The only site allowed during the exam. Spend time getting fast at searching it. Bookmark the Tasks section — that's where etcd backup and kubeadm upgrade live. |
| [Kubernetes Tasks](https://kubernetes.io/docs/tasks/) | The step-by-step pages for etcd backup/restore and kubeadm upgrades, with the cert paths you can copy. Don't skip this. |
| [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/) | Allowed during the exam. The jsonpath examples alone are worth bookmarking. |
| [CKA Curriculum PDF](https://github.com/cncf/curriculum) | Check it before the exam to make sure you haven't missed a topic (Pod Scheduling Readiness is easy to overlook). |
| [Killercoda CKA Scenarios](https://killercoda.com/cka) | Free browser labs, good in short daily sessions. The RBAC and NetworkPolicy ones are the most useful. |

### Paid

| Resource | Honest review | Cost |
|---|---|---|
| [killer.sh](https://killer.sh) | Included with your exam purchase. Two 24-hour sessions. Significantly harder, but the real exam also has tricky questions. If you can pass killer.sh, you're likely ready. Don't waste both sessions early. Save one for the week before. | Free with exam |
| [KodeKloud CKA Course](https://kodekloud.com) | Mumshad's course is a solid start for the first weeks. The built-in labs are what make it worth it, especially for etcd restore. | ~$15-25/mo |
| [Udemy — Mumshad CKA](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/) | Same content as KodeKloud but one-time purchase. Wait for a Udemy sale ($10-15). Either works. | ~$15 |

### Local Practice Environments

| Tool | Notes |
|---|---|
| [kind](https://kind.sigs.k8s.io/) | Used by this repo's lab. Create/destroy clusters in seconds, multi-node clusters for drain/cordon, kubeadm-based nodes you can `ssh` into. |
| [minikube](https://minikube.sigs.k8s.io/) | Single-node, easy setup. Fine for basic exercises but useless for kubeadm upgrade or node troubleshooting. |
| [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/) | The real deal. Set up actual VMs (e.g. Vagrant + VirtualBox) and install with kubeadm. Painful to set up, but this is how you actually learn the cluster architecture domain. |

Advice: don't spend your first 2 weeks watching videos. Spend 30% of your time on theory and 70% hands-on in a real cluster.

---

## CKA Study Plan (4-5 Weeks)

A plan to adapt, not to follow to the letter. If etcd restore (or anything else) isn't clicking, stay on it until you can do it without the docs, even if it pushes the next topic back.

### Week 1 — Foundations

- Set up a practice cluster (kind or minikube)
- Configure aliases and vim ([exam-setup.sh](../../scripts/exam-setup.sh))
- Cover Domain 3 (Workloads & Scheduling): Pods, Deployments, ConfigMaps, Secrets, scheduling
- Practise the Workloads & Scheduling domain in `./cka`
- Practice generating YAML with `$do` — you should never type a full manifest from scratch

### Week 2 — Cluster Administration

- Cover Domain 4 (Cluster Architecture): RBAC, kubeadm, etcd backup/restore
- Set up a multi-node cluster with kubeadm (VMs or cloud)
- Practise the Cluster Architecture domain in `./cka`
- Practice etcd backup/restore until you can do it from memory
- Memorize RBAC imperative commands (create role, create rolebinding, auth can-i)

### Week 3 — Networking + Storage + Troubleshooting

- Cover Domain 5 (Services & Networking): Services, Ingress, NetworkPolicy, CoreDNS
- Cover Domain 1 (Storage): PV, PVC, StorageClass
- Cover Domain 2 (Troubleshooting): start breaking things and fixing them
- Practise Services & Networking, Storage and Troubleshooting in `./cka`
- Do killer.sh session 1
- Usually the hardest week. NetworkPolicy AND storage AND troubleshooting is a lot. If you need to push something to Week 4, push storage.

### Week 4 — Mock Exams + Weak Areas

- Take [mock exams](../lab.md#two-modes) with `./cka` under timed conditions (2 hours)
- Review killer.sh results — identify weak areas
- Redo the questions you failed (`./cka` puts them first)
- Practice context switching discipline — every question, switch context first
- Do killer.sh session 2 (3 days before exam)

### Week 5 (Optional) — Polish

- Only if you didn't feel ready after Week 4
- Focus entirely on weak domains
- Practice speed: can you do a full RBAC setup in under 3 minutes?
- Review the [mistakes list](exam-guide.md#mistakes-that-will-fail-you-on-the-cka) one more time
- A buffer week, just in case

---

## Study Progress Tracker

Track your progress across all CKA domains.

### Domain 1 — Storage (10%)

- [ ] Understand PersistentVolume and PersistentVolumeClaim
- [ ] Understand StorageClass and dynamic provisioning
- [ ] Know access modes (RWO, ROX, RWX, RWOP)
- [ ] Know reclaim policies (Retain, Delete)
- [ ] CSI driver basics and troubleshooting
- [ ] Mount PVC in a Pod
- [ ] Complete [static-pv-rwx](../../questions/static-pv-rwx/)

### Domain 2 — Troubleshooting (30%)

- [ ] Read kubelet logs with journalctl
- [ ] Check control plane pod logs
- [ ] Debug Pending pods
- [ ] Debug CrashLoopBackOff pods
- [ ] Debug ImagePullBackOff
- [ ] Troubleshoot Service endpoints
- [ ] Troubleshoot CoreDNS
- [ ] Troubleshoot NetworkPolicy
- [ ] Use kubectl debug (ephemeral containers + node debug)
- [ ] Complete [cluster-multi-fault](../../questions/cluster-multi-fault/), [kubectl-debug-pod-node](../../questions/kubectl-debug-pod-node/)

### Domain 3 — Workloads & Scheduling (15%)

- [ ] Create and manage Deployments
- [ ] Rolling update and rollback
- [ ] ConfigMaps and Secrets (env and volume)
- [ ] Resource requests and limits
- [ ] HPA (autoscaling/v2)
- [ ] DaemonSet
- [ ] Static pods
- [ ] nodeSelector and node affinity
- [ ] Taints and tolerations
- [ ] Complete [pod-labels-resources](../../questions/pod-labels-resources/), [rollout-rollback](../../questions/rollout-rollback/), [static-pod](../../questions/static-pod/), [hpa-cpu-autoscaling](../../questions/hpa-cpu-autoscaling/)

### Domain 4 — Cluster Architecture (25%)

- [ ] RBAC: Role, ClusterRole, RoleBinding, ClusterRoleBinding
- [ ] kubectl auth can-i for RBAC debugging
- [ ] ServiceAccounts
- [ ] Pod Security Standards (PSS) enforcement
- [ ] kubeadm cluster setup
- [ ] kubeadm cluster upgrade
- [ ] Container runtime configuration (CRI-dockerd, containerd)
- [ ] Understand HA topology
- [ ] Helm install, upgrade, rollback
- [ ] Kustomize base + overlay
- [ ] Complete [rbac-user-and-serviceaccount](../../questions/rbac-user-and-serviceaccount/), [node-drain-maintenance](../../questions/node-drain-maintenance/), [kubeadm-upgrade](../../questions/kubeadm-upgrade/), [helm-upgrade-rollback](../../questions/helm-upgrade-rollback/), [kustomize-base-overlay](../../questions/kustomize-base-overlay/), [cri-dockerd-setup](../../questions/cri-dockerd-setup/), [pss-fix-deployment](../../questions/pss-fix-deployment/)

### Domain 5 — Services & Networking (20%)

- [ ] ClusterIP, NodePort, LoadBalancer services
- [ ] Classic Ingress resources and path-based routing
- [ ] Ingress TLS termination and IngressClass
- [ ] Gateway API (Gateway + HTTPRoute)
- [ ] NetworkPolicy (ingress + egress)
- [ ] CoreDNS configuration
- [ ] CNI plugin awareness
- [ ] Complete [netpol-three-tier](../../questions/netpol-three-tier/), [gateway-traffic-split](../../questions/gateway-traffic-split/), [ingress-tls-paths](../../questions/ingress-tls-paths/)

### Exam Readiness

- [ ] Aliases and vim config memorized
- [ ] CRI-dockerd kernel configuration and setup memorized
- [ ] Can install and configure kubeadm cluster from memory
- [ ] YAML templates written from memory (at least 10)
- [ ] killer.sh session 1 completed
- [ ] killer.sh session 2 completed
- [ ] Mock exam completed (>66%)
- [ ] ID verified and CNCF account name matches
