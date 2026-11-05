# CKA Exercises

32 hands-on labs covering the five official CKA exam domains, plus a small number of clearly marked supplemental labs. Each one has a task list, hints, verification commands, and a full solution behind a spoiler tag. The current [CNCF CKA curriculum](https://github.com/cncf/curriculum/blob/master/CKA_Curriculum_v1.37.pdf) is the source for exam scope; supplemental labs are useful practice, not a claim that the named product or implementation will appear on the exam.

I ordered these roughly by difficulty. If you're short on time, prioritize 09 (kubeadm), 11 (troubleshooting), 29 (etcd fix), and 28 (NetworkPolicy) — those cover the highest-weight domains and represent real exam patterns.

**New in v2.0:** Exercises 23-32 add advanced scenarios and troubleshooting practice.

| # | Exercise | Domain | Difficulty | Time |
|---|---|---|---|---|
| 01 | [Pod Basics](01-pod-basics/) | Workloads & Scheduling | Easy | 10 min |
| 02 | [Multi-Container Pod](02-multi-container-pod/) | Workloads & Scheduling | Medium | 15 min |
| 03 | [ConfigMap & Secret](03-configmap-secret/) | Workloads & Scheduling | Easy | 10 min |
| 04 | [RBAC](04-rbac/) | Cluster Architecture | Medium | 15 min |
| 05 | [NetworkPolicy](05-networkpolicy/) | Services & Networking | Medium | 20 min |
| 06 | [Deployment Rollout](06-deployment-rollout/) | Workloads & Scheduling | Easy | 10 min |
| 07 | [StatefulSet](07-statefulset/) | Workloads & Scheduling | Medium | 15 min |
| 08 | [Node Drain & Cordon](08-node-drain-cordon/) | Cluster Architecture | Easy | 10 min |
| 09 | [kubeadm Upgrade](09-kubeadm-upgrade/) | Cluster Architecture | Hard | 25 min |
| 10 | [Static Pod](10-static-pod/) | Workloads & Scheduling | Easy | 10 min |
| 11 | [Troubleshoot Cluster](11-troubleshoot-cluster/) | Troubleshooting | Hard | 25 min |
| 12 | [Storage — PV & PVC](12-storage-pv-pvc/) | Storage | Medium | 15 min |
| 13 | [Helm Install & Upgrade](13-helm-install-upgrade/) | Cluster Architecture | Medium | 15 min |
| 14 | [Kustomize Overlays](14-kustomize-overlays/) | Cluster Architecture | Medium | 15 min |
| 15 | [Gateway API](15-gateway-api/) | Services & Networking | Medium | 20 min |
| 16 | [Horizontal Pod Autoscaler](16-hpa/) | Workloads & Scheduling | Medium | 15 min |
| 17 | [kubectl debug](17-kubectl-debug/) | Troubleshooting | Medium | 15 min |
| 18 | [CRI-dockerd Setup (supplemental implementation practice)](18-cri-dockerd-setup/) | Cluster Architecture | Medium | 15 min |
| 19 | [Classic Ingress](19-ingress-classic/) | Services & Networking | Medium | 15 min |
| 20 | [Pod Security Standards](20-pod-security-standards/) | Workloads & Scheduling | Medium | 15 min |
| 21 | [Jobs & CronJobs](21-jobs-cronjobs/) | Workloads & Scheduling | Medium | 15 min |
| 22 | [PriorityClass](22-priorityclass/) | Workloads & Scheduling | Medium | 15 min |
| 23 | [Resource Requests Tuning](23-resource-requests-tuning/) | Workloads & Scheduling | Hard | 20 min |
| 24 | [PriorityClass Patch](24-priorityclass-patch/) | Workloads & Scheduling | Medium | 15 min |
| 25 | [Storage WaitForFirstConsumer](25-storage-waitforfirstconsumer/) | Storage | Hard | 20 min |
| 26 | [CRI-dockerd Installation (supplemental implementation practice)](26-cri-dockerd-setup/) | Cluster Architecture | Hard | 30 min |
| 27 | [CNI Tigera/Calico Install](27-cni-tigera-install/) | Cluster Architecture | Hard | 30 min |
| 28 | [Complex NetworkPolicy](28-network-policy-complex/) | Services & Networking | Hard | 25 min |
| 29 | [Troubleshoot etcd Endpoint](29-troubleshoot-etcd-endpoint/) | Troubleshooting | Hard | 20 min |
| 30 | [TLS Configuration Update (supplemental application practice)](30-tls-configuration-update/) | Supplemental | Hard | 20 min |
| 31 | [Argo CD GitOps Setup (supplemental product practice)](31-argocd-gitops-setup/) | Cluster Architecture | Hard | 25 min |
| 32 | [Service Endpoints Troubleshooting](32-service-endpoints-troubleshooting/) | Services & Networking | Medium | 15 min |

| Domain | Weight | Exercises |
|---|---|---|
| Troubleshooting | 30% | 11, 17, 29 |
| Cluster Architecture | 25% | 04, 08, 09, 13, 14, 27 |
| Services & Networking | 20% | 05, 15, 19, 28, 32 |
| Workloads & Scheduling | 15% | 01, 02, 03, 06, 07, 10, 16, 20, 21, 22, 23, 24 |
| Storage | 10% | 12, 25 |

## How to Use

1. Read the exercise description
2. Try the tasks without looking at the solution
3. Use the hints if you're stuck
4. Check your work with the verification steps
5. Compare against the solution
6. Run cleanup before moving to the next exercise

Every exercise assumes you have a running cluster (kind, minikube, or kubeadm) and the aliases from [`scripts/exam-setup.sh`](../scripts/exam-setup.sh).

Contributors changing an exercise can use the [clean-cluster testing checklist](../EXERCISE-TESTING.md) to check setup, verification, and cleanup from a disposable kind cluster.
