[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![Tests](https://github.com/theplatformlab/CKA-Certified-Kubernetes-Administrator/actions/workflows/test.yml/badge.svg)](https://github.com/theplatformlab/CKA-Certified-Kubernetes-Administrator/actions/workflows/test.yml)
[![CKA exam version](https://img.shields.io/badge/CKA%20exam-v1.37-326CE5?logo=kubernetes&logoColor=white)](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks)
[![Lab version](https://img.shields.io/badge/Lab%20version-v1.35-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/releases/)
[![Questions](https://img.shields.io/badge/Lab%20questions-110-blue)](questions/)
[![Certifications](https://img.shields.io/badge/Lab-CKA%20%7C%20CKAD%20%7C%20CKS-326CE5)](LAB.md)
[![Mock Exams](https://img.shields.io/badge/Mock%20Exams-generated-success)](LAB.md)
[![GitHub stars](https://img.shields.io/github/stars/theplatformlab/CKA-Certified-Kubernetes-Administrator?style=social)](https://github.com/theplatformlab/CKA-Certified-Kubernetes-Administrator)

**Disclaimer:** This is a study and practice resource for the CKA, CKAD and CKS exams. It does not include, share, or reproduce actual exam questions. All tasks are independently designed training scenarios. See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for policies.

> A hands-on lab for the CKA, CKAD and CKS (practice sessions and generated mock exams, graded against live kind clusters) plus a CKA study guide: notes, commands, a kubectl cheat sheet and common mistakes. The lab targets Kubernetes v1.35.

**Version check (October 21, 2026):** The Linux Foundation currently lists Kubernetes v1.37 for the exam environments. It says exam environments generally align with a new Kubernetes minor version within about 4 to 8 weeks of release. This repository's lab targets v1.35 unless a file says otherwise; it is not all verified against v1.37. Check the [official FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks) and the CNCF curricula ([CKA](https://github.com/cncf/curriculum/blob/master/CKA_Curriculum_v1.37.pdf), [CKAD](https://github.com/cncf/curriculum), [CKS](https://github.com/cncf/curriculum)) before relying on version-specific details.

# Kubernetes Certification Lab 2026 — CKA, CKAD and CKS

<p align="center">
  <img src="assets/cka.png" alt="Kubernetes certification lab for CKA, CKAD and CKS — practice tasks, mock exams, study guide and cheat sheet">
</p>

This repo is two things. **The lab** (`./cka`) gives you exam-style tasks on local kind clusters for the [CKA](https://www.cncf.io/certification/cka/), [CKAD](https://www.cncf.io/certification/ckad/) and [CKS](https://www.cncf.io/certification/cks/): practice sessions by domain or area, and timed mock exams weighted like each curriculum, all graded against the live cluster state. **The guide** below covers the CKA in depth: exam format, environment, imperative commands, the syllabus by domain, time management and the mistakes that cost the most points.

The CKA, CKAD and CKS are two-hour, performance-based exams completed from a command line. Four weeks of focused practice is a realistic plan for the CKA if you already work with Kubernetes.

If this is useful, a star helps others find it.

---

## Quick Start (< 4 Weeks to Exam)

If you're time-pressured, here's the fast track:

1. **Start a practice cluster** _(if needed)_ — if `kubectl` says connection refused or you don't have a local cluster yet: `bash scripts/init-cluster.sh`. This creates a kind-based k8s 1.35.1 cluster (1 control plane + 2 workers) with one command. [Read more](#local-cluster-setup--practice-with-kind).
2. **Run the setup script** — get your aliases and vim config right from day one: [scripts/exam-setup.sh](scripts/exam-setup.sh)
3. **Practise and take mock exams with `./cka`.** Practice sessions (by domain or area, e.g. Helm & Kustomize) and mock exams are drawn from one pool of exam-style [questions](questions/), for CKA, CKAD or CKS. Mock exams are weighted like the curriculum, graded automatically against the live cluster, and tracked. See [LAB.md](LAB.md).
4. **Use YAML templates** — reference [TEMPLATES.md](TEMPLATES.md). Copy, paste, modify.
5. **Do killer.sh twice** — once 2 weeks out, once 3 days before. See [killer.sh vs the Real Exam](#killersh-vs-the-real-cka-exam).
6. **Read the exam day strategy** — the [two-pass approach](#exam-day-strategy--time-allocation) saved time on exam day.

---

## Repo Structure

```
CKA-Certified-Kubernetes-Administrator/
├── README.md                          # This guide (you're here)
├── LAB.md                             # The lab: practice sessions and mock exams for CKA, CKAD, CKS
├── questions/                         # The task pool (task, hints, solution, setup + validator per item)
├── cka                                # Lab launcher
├── TEMPLATES.md                       # YAML templates in collapsible format
├── tools/cka/                         # The lab app (Go)
├── cheatsheet/
│   └── cka-cheatsheet.md              # One-page printable reference
├── troubleshooting/
│   └── README.md                      # Symptom-based lookup playbook
├── scripts/
│   ├── init-cluster.sh               # kind clusters (profiles in config/)
│   ├── lab.sh                        # Setup / check / cleanup of a single item
│   ├── exam/                         # Docs-only browser proxy, ssh shim, shell rc
│   ├── lib/                          # Shared helpers for the validators
│   └── exam-setup.sh                 # Aliases, vim config, bash completion
├── .github/
│   ├── workflows/test.yml             # CI — app tests (incl. the pool) and item script syntax
│   ├── ISSUE_TEMPLATE/                # Bug, content request, exam feedback
│   │   └── config.yml                 # Discussions link for questions
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/CKS-WSL.md                    # Falco, AppArmor, gVisor on WSL2
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE
```

---

## Table of Contents

### Start Here — Practice Your Skills
- [CKA Syllabus Breakdown (v1.37)](#cka-syllabus-breakdown-v137)
  - [Domain 1 — Storage (10%)](#domain-1--storage-10)
  - [Domain 2 — Troubleshooting (30%)](#domain-2--troubleshooting-30)
  - [Domain 3 — Workloads & Scheduling (15%)](#domain-3--workloads--scheduling-15)
  - [Domain 4 — Cluster Architecture, Installation & Configuration (25%)](#domain-4--cluster-architecture-installation--configuration-25)
  - [Domain 5 — Services & Networking (20%)](#domain-5--services--networking-20)
- [CKA Domain Weight Distribution](#cka-domain-weight-distribution)
- [Practice Scenarios with Full Solutions](#practice-scenarios-with-full-solutions)
- [Mock Exams — Final Preparation](#mock-exams--final-preparation)
- [Study Progress Tracker](#study-progress-tracker)

### Exam Preparation Strategy
- [The Exam Environment (PSI Remote Desktop)](#the-exam-environment-psi-remote-desktop)
- [First 60 Seconds — Aliases, vim, bash](#first-60-seconds--aliases-vim-bash)
- [Imperative Commands Quick Reference](#imperative-commands-quick-reference)
- [YAML Templates Quick Reference](#yaml-templates--write-these-from-memory)
- [Exam Day Strategy — Time Allocation](#exam-day-strategy--time-allocation)
- [Mistakes That Will Fail You on the CKA](#mistakes-that-will-fail-you-on-the-cka)
- [Vim Keys You Need on Exam Day](#vim-keys-you-need-on-exam-day)
- [Troubleshooting Decision Flowchart](#troubleshooting-decision-flowchart)
- [CKA Exam Day Checklist](#cka-exam-day-checklist)

### Study Resources & Planning
- [kubectl Cheat Sheet for CKA](#kubectl-cheat-sheet-for-cka)
- [Docs Pages Worth Bookmarking](#docs-pages-worth-bookmarking)
- [CKA Study Plan (4-5 Weeks)](#cka-study-plan-4-5-weeks)
- [Study Resources for CKA 2026](#study-resources-for-cka-2026)
- [killer.sh vs the Real CKA Exam](#killersh-vs-the-real-cka-exam)

### Exam Details & Reference
- [CKA Exam Details — Cost, Duration, Passing Score, Format](#cka-exam-details--cost-duration-passing-score-format-october-2026)
- [How Much Does the CKA Exam Cost?](#how-much-does-the-cka-exam-cost)
- [CKA vs CKAD vs CKS — Which One Should You Take?](#cka-vs-ckad-vs-cks--which-one-should-you-take)
- [CKA vs CKAD vs CKS Scope Architecture Diagram](#cka-vs-ckad-vs-cks-scope-architecture-diagram)
- [Kubernetes v1.35 Lab Notes](#kubernetes-v135-lab-notes)
- [Before You Book the CKA Exam](#before-you-book-the-cka-exam)
- [CKA FAQ — Common Questions](#cka-faq--common-questions)

### Final Thoughts
- [Final Words](#final-words)

---

## Local Cluster Setup — Practice with Kind

**Don't have a Kubernetes cluster?** Use the included script to bootstrap a local k8s 1.35.1 cluster via [kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker). Perfect for the lab without needing a kubeadm setup.

### Quick Start: One Command

```bash
bash scripts/init-cluster.sh
```

**What it does:**
- ✅ Auto-installs `kind` if missing (v0.31.0)
- ✅ Validates Docker is running
- ✅ Creates cluster `cka-practice` (k8s 1.35.1, 1 control plane + 2 workers)
- ✅ Configures kubeconfig automatically
- ✅ Prints next steps on success

### Cluster Profiles

Some tasks need a cluster you can break or rebuild. Each profile is a separate kind cluster with its own config in [`scripts/config/`](scripts/config/):

| Profile | Cluster | Used for |
|---|---|---|
| `practice` (default) | `cka-practice` | Almost all tasks |
| `ops` | `cka-ops` | kubeadm upgrade and join, static pods, broken control plane, etcd. Every node has the pkgs.k8s.io apt repo for the **next** minor version, so `apt-get install kubeadm=1.36.x-*` + `kubeadm upgrade apply` work like on a real kubeadm cluster. etcdctl is installed. |
| `cni` | `cka-cni` | Created without a CNI, so you install Calico yourself |
| `runtime` | `cka-runtime` | Docker Engine + cri-dockerd on a node |
| `ha` | `cka-ha` | 3 control planes + 1 worker behind a load balancer |
| `cks` | `cka-cks` | CKS tooling on the nodes: Falco, trivy, kube-bench, gVisor ([docs/CKS-WSL.md](docs/CKS-WSL.md)) |

```bash
bash scripts/init-cluster.sh                     # practice
bash scripts/init-cluster.sh --profile ops       # ops (recreate it after each upgrade run)
bash scripts/init-cluster.sh --profile ops --recreate
bash scripts/init-cluster.sh --help
```

**Prerequisites:**
- [Docker](https://docs.docker.com/get-docker/) — installed and running
- `kubectl` — installed (via [official docs](https://kubernetes.io/docs/tasks/tools/) or `brew install kubectl`)
- `jq` and `helm` for some validators, `tmux` and `python3` for the mock exam
- ~5 GB free disk space, ~2 GB RAM per cluster

**Running several clusters:** each kind node uses inotify instances. If a second cluster fails with `too many open files` (containerd) or the kubelet never becomes healthy, raise the limits:

```bash
echo -e 'fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=1048576' | sudo tee /etc/sysctl.d/99-kind.conf
sudo sysctl --system
```

If `kind create` fails with `no available IPv4 addresses`, your `kind` docker network has a small IP range. Put the extra clusters on their own network: `KIND_EXPERIMENTAL_DOCKER_NETWORK=kind-labs bash scripts/init-cluster.sh --profile ops`.

### Practice Sessions, Mock Exams and Validation

`./cka` opens the lab: practice sessions with hints and on-demand checks, and mock exams generated from the pool and weighted like the curriculum. Results are tracked, and items you haven't done or failed come first. See [LAB.md](LAB.md).

Every item can also be run by hand. Each one has a setup step (namespace, pre-existing or deliberately broken objects) and a validator that checks the end state of your solution:

```bash
./scripts/lab.sh list                    # all items and the cluster each one uses
./scripts/lab.sh setup rollout-rollback  # items are addressed by their directory name
./scripts/lab.sh check rollout-rollback  # ✓/✗ per requirement, exit code 0 when everything passes
./scripts/lab.sh cleanup rollout-rollback
```

The runner always talks to the item's cluster (`--context kind-cka-practice`, `kind-cka-ops`, ...), whatever your current context is.

**After setup:**
1. Run the exam-setup script to configure aliases: `bash scripts/exam-setup.sh`
2. Verify connection: `kubectl get nodes` — should show `cka-practice-control-plane`, `cka-practice-worker` and `cka-practice-worker2`
3. Start the lab: `./cka`

### Using Your Own Cluster

If you already have:
- A kubeadm cluster (bare metal / VMs)
- An existing kind cluster
- A cloud cluster (EKS, GKE, AKS) — **not recommended for CKA practice** (different tooling)

Then skip init-cluster.sh and just run:
```bash
bash scripts/exam-setup.sh        # Configure aliases, etc.
kubectl get nodes                 # Verify connection
./cka                             # Start practicing
```

---

## CKA Exam Details — Cost, Duration, Passing Score, Format (October 2026)

| **CKA Exam Details**               | **Information**                                                                                                                                     |
|------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| **Exam Type**                      | Performance-based (live terminal — NOT multiple choice)                                                                                             |
| **Exam Duration**                  | 2 hours                                                                                                                                             |
| **Passing Score**                  | 66%                                                                                                                                                 |
| **Kubernetes Version**             | v1.37, according to the Linux Foundation FAQ checked October 21, 2026                                                                                |
| **Number of Questions**            | The official overview describes a performance-based exam; it does not give a fixed task count                                                       |
| **Exam Cost**                      | $445 USD (includes one free retake)                                                                                                                 |
| **Certificate Validity**           | 2 years                                                                                                                                             |
| **Exam Delivery**                  | PSI Secure Browser (remote proctored)                                                                                                               |
| **Allowed Resources**              | kubernetes.io/docs, kubernetes.io/blog, github.com/kubernetes — open in exam browser                                                                |
| **Domains Covered**               | 5 domains: Storage, Troubleshooting, Workloads & Scheduling, Cluster Architecture, Services & Networking                                            |
| **Exam Language**                  | English, Japanese, Simplified Chinese                                                                                                                |
| **OS in Exam**                     | Ubuntu Linux terminal                                                                                                                                |

Important: the passing score is 66%, not 75% like some older guides say. They lowered it. Still not easy though — 2 hours goes fast when you're troubleshooting a broken kubelet under pressure.

[Back to top](#table-of-contents)

---

## How Much Does the CKA Exam Cost?

The Linux Foundation listed the exam-only option at **$445 USD** in October 2026. Bundles, retake eligibility, simulator access, and course access depend on the option shown at purchase and can change. Check the [official CKA page](https://training.linuxfoundation.org/certification/certified-kubernetes-administrator-cka/) for current details; promotions regularly lower the price.

---

## CKA vs CKAD vs CKS — Which One Should You Take?

| | **CKA** | **CKAD** | **CKS** |
|---|---|---|---|
| **Focus** | Cluster administration | Application development | Security |
| **Who it's for** | SREs, platform engineers, admins | Developers deploying to K8s | Security engineers, senior admins |
| **Difficulty** | Hard — the troubleshooting and etcd questions are brutal under time pressure | Medium — if you already deploy to K8s, most of this is familiar | Hardest of the three — Falco and AppArmor syntax is miserable to memorize |
| **Duration** | 2 hours | 2 hours | 2 hours |
| **Passing Score** | 66% | 66% | 67% |
| **Cost** | $445 | $445 | $445 |
| **Prerequisites** | None | None | Must hold active CKA |
| **Key Topics** | etcd, kubeadm, RBAC, troubleshooting, networking | Pods, Deployments, Jobs, probes, volumes | Falco, AppArmor, OPA, Network Policies, audit |
| **Recommendation** | Start here if you manage clusters. The etcd and kubeadm skills don't exist anywhere else. | Easier than CKA but less impressive on a resume. | Take it if your job involves cluster security — it requires an active CKA. |

In short: if you're doing any kind of cluster administration, start with CKA. If you're purely a dev who deploys apps, CKAD first. CKS requires an active CKA, so you can't skip it. The lab in this repo covers all three from one pool of tasks.

There's about 40% overlap between CKA and CKAD (pods, deployments, services, configmaps, secrets). If you pass one, the other is easier. CKA first makes sense for most people, because troubleshooting and etcd backup are harder to learn on your own.

---

## CKA vs CKAD vs CKS Scope Architecture Diagram

```mermaid
graph TB
    subgraph CKA["CKA — Cluster Administration"]
        style CKA fill:#326CE5,color:#fff
        A1[etcd backup/restore]
        A2[kubeadm install/upgrade]
        A3[RBAC — Roles, ClusterRoles]
        A4[Node management — drain, cordon]
        A5[Troubleshooting — kubelet, kube-proxy, CoreDNS]
        A6[Cluster networking — CNI, Services]
        A7[Storage — PV, PVC, StorageClass]
    end
    
    subgraph CKAD["CKAD — Application Development"]
        style CKAD fill:#00A86B,color:#fff
        B1[Multi-container pods — sidecars, init]
        B2[Jobs, CronJobs]
        B3[Probes — liveness, readiness, startup]
        B4[Helm charts]
        B5[Custom Resource Definitions]
        B6[Blue/green, canary deployments]
    end
    
    subgraph SHARED["Shared (~40% overlap)"]
        style SHARED fill:#FF8C00,color:#fff
        S1[Pods, Deployments, Services]
        S2[ConfigMaps, Secrets]
        S3[NetworkPolicies]
        S4[Ingress / Gateway API]
        S5[Labels, selectors, annotations]
        S6[Resource requests/limits]
    end
    
    subgraph CKS["CKS — Security"]
        style CKS fill:#DC143C,color:#fff
        C1[Falco runtime security]
        C2[AppArmor / Seccomp profiles]
        C3[OPA Gatekeeper]
        C4[Audit logging]
        C5[Image scanning — Trivy]
        C6[Pod Security Standards]
        C7[Supply chain security]
    end
    
    CKA -->|"~40% overlap"| CKAD
    CKA -->|"required for"| CKS
```

---

## Kubernetes v1.35 Lab Notes

These notes describe the repository's v1.35 lab baseline. They are not a list of changes guaranteed to appear on the current CKA exam. For exam scope, use the current [official curriculum](https://github.com/cncf/curriculum/blob/master/CKA_Curriculum_v1.37.pdf).

| Feature | Status in v1.35 | Lab note |
|---|---|---|
| **Native sidecars** | Stable | Sidecars can be declared in `initContainers` with `restartPolicy: Always`. |
| **In-place pod vertical scaling** | Beta | Can resize CPU or memory resources without replacing the pod, subject to feature support. |
| **Gateway API** | Stable APIs available | See the Gateway API questions; controller installation and configuration vary by cluster. |
| **kubectl debug** | Stable | The command is useful for pod and node troubleshooting. |
| **ValidatingAdmissionPolicy** | Stable | CEL-based admission policy is available without a webhook. |

Check the documentation for the Kubernetes version used by your practice cluster before using version-specific features.

---

## Before You Book the CKA Exam

A checklist before you book:

1. **Can you set up a cluster from scratch with kubeadm?** It usually takes a few attempts before you can do it without the docs open. Do it at least twice before booking.
2. **Can you do an etcd backup and restore?** It is an important cluster-administration skill. Practice the snapshot commands and know how to verify the restored data; use the docs for version-specific flags.
3. **Are you comfortable with RBAC?** Role vs ClusterRole, RoleBinding vs ClusterRoleBinding, ServiceAccounts — the `--as=system:serviceaccount:ns:name` syntax takes a while to click.
4. **Can you troubleshoot a NotReady node?** SSH in, check kubelet, check certificates, check networking. This is 30% of the score and it's the section where most people lose the most time.
5. **Do you have a cluster to practice on?** kind or minikube on your laptop, or Killercoda/KodeKloud online. You cannot pass this exam by reading — you have to break things.
6. **Have you done killer.sh at least once?** killer.sh is good practice but don't assume the real exam is easier. Both have tricky questions. killer.sh builds speed and confidence, which matters more. A low first killer.sh score is normal.
7. **Is your ID ready?** Government-issued ID, matching your CNCF account name. Check this before exam day.

---

## The Exam Environment (PSI Remote Desktop)

The exam runs in a PSI Secure Browser — a remote Ubuntu desktop. Things that surprise people:

**Copy/Paste:**
- `Ctrl+Shift+C` / `Ctrl+Shift+V` in the terminal
- Right-click paste works sometimes, sometimes it doesn't
- The built-in notepad uses normal `Ctrl+C` / `Ctrl+V`
- Practice these shortcuts. Fumbling with paste in the first question easily costs two minutes.

**Terminal quirks:**
- There's a small delay on every keystroke — maybe 50-100ms. It adds up.
- Tab completion works but feels laggy.
- You can open multiple terminal tabs. Two work well: one for the task, one for verification.
- The file browser is basic. Stick to command line.

**Browser:**
- One extra tab allowed for kubernetes.io documentation
- Bookmarks are not available — you'll type URLs manually
- The search on kubernetes.io is your best friend. Use it instead of navigating.

**General:**
- Webcam and mic are on the entire time
- Clear your desk — nothing on it except your computer
- No second monitor
- No headphones/earphones
- Water bottle is fine (clear, no label)
- Bathroom breaks are allowed but the timer doesn't pause

---

## Important: Exam Environment vs Practice

**In the exam, each question is a fresh SSH connection.** Any aliases or configuration you set up will NOT carry over to the next question. Do not waste exam time on setup.

**Only reliable shortcut:** The `k` alias for `kubectl` is pre-configured on every machine.

**For practice on your laptop,** you can use the setup script in [`scripts/exam-setup.sh`](scripts/exam-setup.sh) to speed up drilling. But practice without these shortcuts 1-2 weeks before the exam to build command muscle memory. You need to know:
- `kubectl run ...`
- `kubectl create ...`
- `--dry-run=client -o yaml` (type it out, not an alias)
- `--force --grace-period=0` (type it out, not an alias)

Memorize the commands. That beats any alias on test day.

---

## Imperative Commands Quick Reference

**Why imperative?** Under the two-hour exam limit, typing YAML can be slow. Use imperative commands when they are faster; use a manifest when the task needs fields that a command cannot express.

**Speed tip:** Memorize these command patterns. On test day, `kubectl run`, `kubectl create`, and `kubectl expose` will be your fastest friends.

### Fast Pod Creation (15-30 seconds vs 2 minutes for YAML)

```bash
# Basic pod
k run nginx --image=nginx:1.27

# Pod with port exposed
k run nginx --image=nginx:1.27 --port=80

# Pod with labels
k run nginx --image=nginx:1.27 --labels=app=web,tier=frontend

# There is no direct command to run pod with resource limits, instead you can use dry-run then edit file or use --overrides arg
k run nginx --image=nginx --overrides='{"spec":{"containers":[{"name":"nginx","image":"nginx","resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}}]}}'

# Pod with environment variables
k run nginx --image=nginx:1.27 --env=LOG_LEVEL=debug --env=APP_ENV=prod

# Pod with command override
k run nginx --image=nginx:1.27 -- sh -c "echo 'Hello' && sleep 3600"

# Pod with multiple containers (init + app)
k run myapp --image=myapp:1.0 --overrides='{"spec":{"initContainers":[{"name":"init","image":"busybox","command":["wget","-O","/data/file","http://example.com"]}],"containers":[{"name":"myapp","image":"myapp:1.0","volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","emptyDir":{}}]}}'

# Generate YAML without running (for review/editing)
k run nginx --image=nginx:1.27 $do > pod.yaml
```

**Exam pattern:** Use `$do` flag to generate YAML, review it, then apply. Saves you from memorizing exact YAML structure.

### Deployment Creation & Management

```bash
# Basic deployment
k create deployment webapp --image=nginx:1.27

# Deployment with replicas
k create deployment webapp --image=nginx:1.27 --replicas=3

# Deployment with resource requests
k create deployment webapp --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml | \
  sed 's/resources: {}/resources:\n              requests:\n                cpu: 100m\n                memory: 128Mi/' > deploy.yaml

# Scale deployment
k scale deployment webapp --replicas=5

# Update image (rolling update)
k set image deployment/webapp nginx=nginx:1.28 --record

# Check rollout status
k rollout status deployment/webapp

# View rollout history
k rollout history deployment/webapp

# Rollback to previous version
k rollout undo deployment/webapp

# Rollback to specific revision
k rollout undo deployment/webapp --to-revision=2

# Pause rollout (for manual canary)
k rollout pause deployment/webapp

# Resume rollout
k rollout resume deployment/webapp

# Generate deployment YAML
k create deployment webapp --image=nginx:1.27 --dry-run=client -o yaml > deploy.yaml
```

**Practice tip:** Know how to inspect rollout history and undo a Deployment update. These are useful administration skills; this guide cannot predict how often they will appear on an exam.

### Service Exposure (ClusterIP, NodePort, LoadBalancer)

```bash
# Expose deployment as ClusterIP (default, internal only)
k expose deployment webapp --port=80 --target-port=8080

# Expose as NodePort (accessible on all nodes)
k expose deployment webapp --port=80 --target-port=8080 --type=NodePort

# Expose as LoadBalancer (cloud-only)
k expose deployment webapp --port=80 --target-port=8080 --type=LoadBalancer

# Get service external IP (NodePort/LoadBalancer)
k get svc -w

# Expose a pod directly (not recommended but does work)
k expose pod nginx --port=80 --name=web-svc

# Create service without deploying (generate YAML)
k create service clusterip web --tcp=80:8080 $do > svc.yaml
k create service nodeport web --tcp=80:8080 $do > svc.yaml

# Edit service after creation
k edit svc webapp

# Port forward for testing (like accessing the pod locally)
k port-forward svc/webapp 8080:80
```

**Exam pattern:** Most questions ask: "Expose deployment X on port Y." Use `k expose deployment X --port=Y --target-port=<app-port>`.

### RBAC — Roles, ServiceAccounts, RoleBindings (25% of exam)

```bash
# Create ServiceAccount
k create sa my-app -n prod

# Create Role (allow specific verbs on specific resources)
k create role pod-reader --verb=get,list,watch --resource=pods -n prod
k create role pod-deleter --verb=get,list,delete --resource=pods -n prod

# Create RoleBinding (bind role to user/sa)
k create rolebinding read-pods --role=pod-reader --serviceaccount=prod:my-app -n prod

# ClusterRole (cross-namespace)
k create clusterrole node-reader --verb=get,list --resource=nodes

# ClusterRoleBinding
k create clusterrolebinding read-nodes --clusterrole=node-reader --serviceaccount=prod:my-app

# Check if user/SA has permission
k auth can-i list pods -n prod --as=system:serviceaccount:prod:my-app

# Check your own permissions
k auth can-i list pods -n prod

# View role details
k get role pod-reader -n prod -o yaml
k get rolebinding read-pods -n prod -o yaml

# Edit role to add/remove permissions
k edit role pod-reader -n prod
```

**Exam tip:** RBAC questions usually involve creating SA + Role + RoleBinding, then testing with `k auth can-i`. Practice the syntax until you don't have to think.

### ConfigMaps & Secrets (Application config)

```bash
# ConfigMap from literal values
k create configmap app-config --from-literal=LOG_LEVEL=debug --from-literal=DB_HOST=postgres.prod

# ConfigMap from file
k create configmap app-config --from-file=config.properties

# ConfigMap from directory
k create configmap app-config --from-file=./configs/

# Secret from literal
k create secret generic db-secret --from-literal=username=admin --from-literal=password=secret123

# Secret from file
k create secret generic tls-secret --from-file=tls.crt=cert.pem --from-file=tls.key=key.pem

# Docker registry secret (for pulling private images)
k create secret docker-registry dockerhub --docker-server=docker.io --docker-username=myuser --docker-password=mypass

# View secret (NOT decrypted)
k get secret db-secret -o yaml

# Describe configmap
k describe cm app-config
```

**Exam pattern:** When a question mentions "app needs config from file," use `k create configmap $name --from-file`.

### Node Management (Maintenance, upgrades, troubleshooting)

```bash
# Cordon node (mark unschedulable, don't evict existing pods)
k cordon node-1

# Drain node (evict all pods before maintenance)
k drain node-1 --ignore-daemonsets --delete-emptydir-data

# Uncordon node (resume scheduling)
k uncordon node-1

# Label a node
k label nodes node-1 disk=ssd
k label nodes node-1 disk=ssd --overwrite  # update existing

# Taint a node (prevent pods from scheduling)
k taint nodes node-1 key=value:NoSchedule
k taint nodes node-1 key=value:NoExecute   # evict existing pods

# Remove taint
k taint nodes node-1 key-

# Get node info (CPU, memory, conditions)
k describe node node-1

# Check node status
k get nodes -o wide
```

**Exam pattern:** "Prepare node for maintenance" = `k drain`. "Node is full" = label it and use nodeSelector. "Node needs maintenance" = `k cordon` + `k drain`.

### Debugging & Troubleshooting (30% of exam — learn this well)

```bash
# Get pod logs (follow in real-time)
k logs pod-name
k logs pod-name -f
k logs pod-name --tail=50

# Logs from previous crashed pod
k logs pod-name --previous

# Logs from all containers in pod
k logs pod-name --all-containers

# Logs from specific container in multi-container pod
k logs pod-name -c container-name

# Short-lived troubleshooting — exec into pod
k exec -it pod-name -- /bin/bash
k exec -it pod-name -c container-name -- /bin/bash

# One-off command in pod
k exec pod-name -- curl http://localhost:8080

# Describe pod (events, conditions, resource usage)
k describe pod pod-name

# Describe everything about a resource
k describe node node-1

# Watch events in real-time
k get events -w

# Get specific event from a namespace
k get events -n prod --sort-by='.lastTimestamp'

# Port forward to debug (useful when service isn't working)
k port-forward pod-name 8080:8080
k port-forward svc/service-name 8080:8080

# Copy files from pod to local (for log inspection)
k cp pod-name:/var/log/app.log ./app.log

# Check resource metrics (requires metrics-server)
k top nodes
k top pods -n prod
```

**Exam tip:** 30% of exam is "troubleshoot why this isn't working." `k describe` and `k logs` are your debugging weapons. Learn to read the error messages.

### Resource Quotas & Limits (Cluster resource management)

```bash
# Create LimitRange (per-pod limits)
k create limitrange cpu-limit --max=2 --min=100m --type=Pod

# Resource quota (per-namespace total limits)
k create quota my-quota --hard=requests.cpu=10,limits.cpu=20,requests.memory=100Gi,pods=100

# Check current usage
k describe resourcequota my-quota -n prod
k describe limitrange cpu-limit -n prod
```

**Exam pattern:** Usually appears as "create resource quota so namespace doesn't exceed X CPU."

### Shortcuts & Pro Tips (Save 5-10 minutes per exam)

```bash
# Dry-run + output to file (review before applying)
k create deployment app --image=app:1.0 $do > deploy.yaml
k apply -f deploy.yaml

# Delete resources fast
k delete pod pod-name $now          # force deletion
k delete pods --all -n prod --now   # delete all pods in namespace
k delete deployment webapp -n prod  # cascade delete (pods too)

# Get resources in all namespaces
k get pods -A
k get pods --all-namespaces

# Get in custom columns (useful for spotting issues)
k get pods -o wide                  # show node, IP, etc.
k get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image

# JSONPath queries (find pods by image)
k get pods -o jsonpath='{.items[*].metadata.name}' | xargs -I{} echo {}

# Get yaml for an existing resource then copy it
k get deployment webapp -o yaml > webapp-backup.yaml
k apply -f webapp-backup.yaml

# Edit resource live
k edit deployment webapp

# Patch resource (update specific field)
k patch deployment webapp -p '{"spec":{"replicas":5}}'
```

---

## Docs Pages Worth Bookmarking

You can access kubernetes.io during the exam. These are the pages worth knowing how to find quickly:

| Topic | Page |
|---|---|
| kubectl cheat sheet | https://kubernetes.io/docs/reference/kubectl/cheatsheet/ |
| etcd backup/restore | https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/ |
| kubeadm upgrade | https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/ |
| RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| PV / PVC | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ |
| Static pods | https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/ |
| Taints and tolerations | https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| Debug services | https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/ |
| CoreDNS | https://kubernetes.io/docs/tasks/administer-cluster/coredns/ |
| Ingress | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| Gateway API | https://kubernetes.io/docs/concepts/services-networking/gateway/ |
| Drain a node | https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/ |

Tip: use the search bar on kubernetes.io. Don't waste time clicking through navigation menus.

---

## kubectl Cheat Sheet for CKA

These are the commands you need most during the exam. All using the aliases from the setup section.

### Context and Namespace

```bash
# Switch context (DO THIS BEFORE EVERY QUESTION)
k config use-context <context-name>

# Set default namespace
kn <namespace>

# Check current context
k config current-context
```

### Pods

```bash
# Create a pod
k run nginx --image=nginx:1.27

# Create pod YAML without running it
k run nginx --image=nginx:1.27 $do > pod.yaml

# Pod with labels
k run nginx --image=nginx:1.27 --labels=app=web,tier=frontend

# Pod with port
k run nginx --image=nginx:1.27 --port=80

# Get pods with extra info
k get pods -o wide
k get pods --show-labels
k get pods -l app=web

# Delete pod fast
k delete pod nginx $now
```

### Deployments

```bash
# Create deployment
k create deployment webapp --image=nginx:1.27 --replicas=3

# Generate YAML
k create deployment webapp --image=nginx:1.27 --replicas=3 $do > deploy.yaml

# Scale
k scale deployment webapp --replicas=5

# Update image
k set image deployment/webapp nginx=nginx:1.28

# Rollout commands
k rollout status deployment/webapp
k rollout history deployment/webapp
k rollout undo deployment/webapp
k rollout undo deployment/webapp --to-revision=2
```

### Services

```bash
# Expose a deployment
k expose deployment webapp --port=80 --target-port=80 --type=ClusterIP
k expose deployment webapp --port=80 --target-port=80 --type=NodePort

# Expose a pod
k expose pod nginx --port=80 --name=nginx-svc

# Generate service YAML
k create service clusterip my-svc --tcp=80:80 $do > svc.yaml
```

### RBAC

```bash
# Create ServiceAccount
k create sa my-sa -n my-ns

# Create Role
k create role pod-reader --verb=get,list,watch --resource=pods -n my-ns

# Create RoleBinding
k create rolebinding read-pods --role=pod-reader --serviceaccount=my-ns:my-sa -n my-ns

# Create ClusterRole
k create clusterrole node-reader --verb=get,list --resource=nodes

# Create ClusterRoleBinding
k create clusterrolebinding read-nodes --clusterrole=node-reader --serviceaccount=my-ns:my-sa

# Check permissions
k auth can-i list pods -n my-ns --as=system:serviceaccount:my-ns:my-sa
```

### Node Management

```bash
# Cordon (mark unschedulable)
k cordon <node-name>

# Drain (evict pods)
k drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon
k uncordon <node-name>

# Label a node
k label node <node-name> disk=ssd

# Taint a node
k taint nodes <node-name> key=value:NoSchedule

# Remove a taint
k taint nodes <node-name> key=value:NoSchedule-
```

### etcd

```bash
# Snapshot
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify snapshot
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-table

# Restore
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored
```

### Troubleshooting

```bash
# Node issues
k get nodes
k describe node <node-name>
ssh <node> -- sudo systemctl status kubelet
ssh <node> -- sudo journalctl -u kubelet --no-pager | tail -30

# Pod issues
k describe pod <pod-name>
k logs <pod-name>
k logs <pod-name> -c <container-name>
k logs <pod-name> --previous

# Service/endpoint issues
k get endpoints <service-name>
k get svc
k describe svc <service-name>

# DNS
k run test-dns --image=busybox:1.36 --rm -it -- nslookup kubernetes
k get pods -n kube-system -l k8s-app=kube-dns

# Debug node
k debug node/<node-name> -it --image=busybox:1.36
```

### Quick YAML Generation

```bash
# Pod
k run nginx --image=nginx:1.27 $do > pod.yaml

# Deployment
k create deployment webapp --image=nginx:1.27 $do > deploy.yaml

# Service
k expose deployment webapp --port=80 $do > svc.yaml

# Job
k create job my-job --image=busybox:1.36 -- sh -c "echo done" $do > job.yaml

# CronJob
k create cronjob my-cron --image=busybox:1.36 --schedule="*/5 * * * *" -- sh -c "echo tick" $do > cron.yaml

# ConfigMap
k create configmap my-cm --from-literal=key=value $do > cm.yaml

# Secret
k create secret generic my-secret --from-literal=pass=s3cret $do > secret.yaml
```

[Back to top](#table-of-contents)

---

## CKA Syllabus Breakdown (v1.37)

The domain weights below match the current official CKA curriculum. The Kubernetes version in the exam environment can change; see the version note near the top of this guide.

### Domain 1 — Storage (10%)

10% of the score. Sounds small, but the questions are straightforward if you understand PV/PVC binding — easy points that are easy to skip in a study plan. The main trap: `storageClassName` has to match exactly between PV and PVC, and "exactly" includes the case where one side has it set and the other doesn't.

> See also: [Storage](questions/static-pv-rwx/) | [YAML templates](TEMPLATES.md)

#### 1.1 — Understand Storage Classes and Persistent Volumes

Storage on Kubernetes is simple in concept but annoying in practice. A **PV** is the actual storage (think: the hard drive). A **PVC** is a request for that storage (think: "I need 2Gi of disk"). A **StorageClass** tells Kubernetes how to dynamically create PVs when a PVC asks for one.

What actually matters for the exam:
- PV is cluster-scoped (no namespace). PVC is namespace-scoped. A PVC in the wrong namespace binds fine, but the pod can't see it.
- PVC binds to a PV when: capacity >= request, accessModes match, AND storageClassName matches. If any one of these is off, the PVC sits in `Pending` forever with no helpful error message.
- The `storageClassName` trap is real. `manual` ≠ `Manual` ≠ empty string. Triple-check it.

```yaml
# PV — cluster-scoped
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /data/my-pv
```

```yaml
# PVC — namespace-scoped
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
  namespace: default
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: manual
```

```yaml
# Pod using PVC
apiVersion: v1
kind: Pod
metadata:
  name: storage-pod
spec:
  containers:
  - name: app
    image: nginx:1.27
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: my-pvc
```

#### 1.2 — Understand Volume Mode, Access Modes, and Reclaim Policies

**Access Modes** — you need to know the four-letter abbreviations:

| Mode | Short | What it actually means |
|---|---|---|
| ReadWriteOnce | RWO | One node can mount read-write. This is what you'll use 90% of the time. |
| ReadOnlyMany | ROX | Many nodes can mount read-only. Rarely comes up on the exam. |
| ReadWriteMany | RWX | Many nodes can mount read-write. Doesn't work with hostPath. |
| ReadWriteOncePod | RWOP | Only one pod can mount read-write. New in v1.29+, might show up. |

> CKA-safe rule: `ReadWriteOnce` is node-scoped, not pod-scoped. `ReadWriteOncePod` is the pod-scoped mode. In real clusters, multiple pods on the same node can often use the same `RWO` volume; `RWOP` is the one that enforces a single pod.

**Reclaim Policies** — know the difference or you'll lose data:

| Policy | What actually happens |
|---|---|
| Retain | PV survives PVC deletion. Data is safe but you have to manually clean up the PV before it can be reused. |
| Delete | PV and the underlying storage get nuked. This is the default for most cloud StorageClasses. Be careful. |
| Recycle | Deprecated. Don't use it, don't memorize it. |

**Volume Modes:**
- `Filesystem` (default) — mounted as a directory
- `Block` — raw block device, no filesystem

On the exam: know the difference between Retain and Delete. If the question says "data should persist after PVC deletion," use Retain.

#### 1.3 — Configure Applications with Persistent Storage

The pattern is always the same:
1. Create PV (or let StorageClass provision it dynamically)
2. Create PVC referencing the StorageClass
3. Mount PVC in the Pod spec

```yaml
# StorageClass for dynamic provisioning
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

`WaitForFirstConsumer` delays binding until a pod actually needs the volume. This avoids scheduling issues where the PV is on node A but the pod lands on node B.

Common gotcha: forgetting `storageClassName`. If the PVC has `storageClassName: ""` (empty string), it only binds to PVs with no StorageClass. If you set `storageClassName: manual`, the PV must also have `storageClassName: manual`.

---

### Domain 2 — Troubleshooting (30%)

This is the biggest domain — 30% of the score. You'll get several questions asking you to fix broken things. Without a system, it is easy to lose time checking pods, then nodes, then pods again. A consistent troubleshooting order (nodes → kubelet → control plane pods → describe → logs → endpoints) makes you much faster and more accurate.

> See also: [Troubleshoot Cluster](questions/cluster-multi-fault/) | [Troubleshooting Decision Flowchart](#troubleshooting-decision-flowchart)

#### 2.1 — Evaluate Cluster and Node Logging

Where to find logs:

| Component | Log Location |
|---|---|
| kubelet | `journalctl -u kubelet` (systemd service) |
| kube-apiserver | `/var/log/kube-apiserver.log` or `k logs -n kube-system kube-apiserver-<node>` |
| kube-scheduler | `k logs -n kube-system kube-scheduler-<node>` |
| kube-controller-manager | `k logs -n kube-system kube-controller-manager-<node>` |
| etcd | `k logs -n kube-system etcd-<node>` |
| Container runtime | `journalctl -u containerd` |

Control plane components run as static pods (in `/etc/kubernetes/manifests/`), so you can check their logs with `k logs`. But kubelet is a systemd service — use `journalctl`.

```bash
# Check node status
k get nodes
k describe node <node-name>

# Check kubelet on a node
ssh <node>
sudo systemctl status kubelet
sudo journalctl -u kubelet --no-pager | tail -50

# Check control plane pods
k get pods -n kube-system
```

#### 2.2 — Monitor Applications

Honestly, monitoring during the exam boils down to two things: `k describe` and `k get events`. `k top` needs metrics-server, which isn't available on every cluster — but know it exists in case a task asks for it.

```bash
# These two are 90% of exam monitoring
k describe pod <pod-name>       # events section at bottom tells you everything
k get events --sort-by='.lastTimestamp'

# The rest — know them, probably won't need them
k get pods
k top pods
k top nodes
k get events -n <namespace> --field-selector reason=Failed
```

#### 2.3 — Container stdout/stderr Logs

The two you'll actually use on the exam: `k logs <pod>` and `k logs <pod> --previous`. The rest are nice-to-know; `-f` and `--tail` rarely matter under exam time pressure.

```bash
# The essentials
k logs <pod-name>
k logs <pod-name> --previous                 # crashed container — you'll use this a lot
k logs <pod-name> -c <container-name>         # multi-container pods

# Rarely needed on the exam but useful
k logs <pod-name> -f
k logs <pod-name> --tail=50
k logs -l app=web --all-containers
```

#### 2.4 — Troubleshoot Application Failure

The exam gives you a broken pod and you figure out why. After enough practice, you develop a reflex based on the status:

**Pending** — this is the most common one on the exam. 9 times out of 10 it's one of these:
- PVC not bound → `k get pvc` — check storageClassName matches
- Taint with no toleration → `k describe node` and look at Taints
- No resources available → `k describe pod` events will say "Insufficient cpu"
- Node selector or affinity doesn't match any node → check labels
- A Pending pod can simply need a namespace ResourceQuota increased — check quotas early

**CrashLoopBackOff** — the container starts and dies immediately:
- `k logs <pod> --previous` first. Always. The error is usually obvious.
- Wrong command/entrypoint is the sneaky one — `["sh", "-c"]` vs `["sh -c"]` is easy to miss
- Missing config (env vars, configmaps, secrets)

**ImagePullBackOff** — almost always a typo in the image name. Seriously. Check the image string character by character.
- Private registry without imagePullSecrets is the other cause, but rare on the exam

**Error / Failed:**
- `k describe pod` events section → `k logs` → you'll find it

```bash
# Systematic pod debugging
k get pod <pod> -o wide          # which node? what IP?
k describe pod <pod>             # events, conditions
k logs <pod>                     # app logs
k logs <pod> --previous          # if it crashed
k exec <pod> -- cat /etc/resolv.conf   # DNS config
k exec <pod> -- env                     # env vars loaded?
```

#### 2.5 — Troubleshoot Cluster Component Failure

When the whole cluster is broken:

```bash
# 1. Are nodes ready?
k get nodes

# 2. Are control plane pods running?
k get pods -n kube-system

# 3. Is kubelet running on the node?
ssh <node>
sudo systemctl status kubelet
sudo systemctl restart kubelet    # try restarting

# 4. Check kubelet logs
sudo journalctl -u kubelet --no-pager | tail -50

# 5. Are certificates expired?
sudo kubeadm certs check-expiration

# 6. Is etcd healthy?
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 7. Check static pod manifests
ls /etc/kubernetes/manifests/
# Should have: etcd.yaml, kube-apiserver.yaml, kube-controller-manager.yaml, kube-scheduler.yaml
```

Common causes:
- kubelet not running → `systemctl start kubelet`
- Wrong static pod manifest → fix YAML in `/etc/kubernetes/manifests/`
- Certificates expired → `kubeadm certs renew all`
- etcd data directory wrong → check `--data-dir` in etcd manifest
- kube-apiserver flag wrong → check manifest, fix, wait for restart

#### 2.6 — Troubleshoot Networking

Service not reachable? Work through this:

```bash
# 1. Does the service exist and have the right selector?
k get svc <service>
k describe svc <service>

# 2. Does the service have endpoints?
k get endpoints <service>
# If empty: selector doesn't match any running pod

# 3. Is the pod actually running on the target port?
k exec <pod> -- wget -qO- localhost:<port>

# 4. DNS working?
k run test-dns --image=busybox:1.36 --rm -it -- nslookup <service-name>

# 5. Is kube-proxy running?
k get pods -n kube-system -l k8s-app=kube-proxy

# 6. NetworkPolicy blocking traffic?
k get networkpolicy -n <namespace>
```

The most common networking issues on the exam:
- Service selector doesn't match pod labels (typo in labels)
- Service targetPort doesn't match container port
- NetworkPolicy denying traffic (remember: any policy = deny by default for that pod)
- CoreDNS down or misconfigured
- kube-proxy not running on a node

---

### Domain 3 — Workloads & Scheduling (15%)

15% of the score. Deployments, rolling updates, ConfigMaps, Secrets, static pods, scheduling constraints. For most people the most comfortable domain, because it's what you do day-to-day. The gotcha: static pods. Deleting them with kubectl just brings them back. Once you understand the kubelet manages them directly, it clicks.

> See also: [Pod Basics](questions/pod-labels-resources/) | [Deployment Rollout](questions/rollout-rollback/) | [Static Pod](questions/static-pod/)

#### 3.1 — Understand Deployments and How to Perform Rolling Updates and Rollbacks

Deployments manage ReplicaSets, which manage Pods. When you update the image, Kubernetes creates a new ReplicaSet and gradually shifts pods over. A common trap: the container name in `k set image` is the container name from the pod spec, not the deployment name. `k set image deployment/webapp webapp=nginx:1.27` fails when the container is actually called `nginx`.

```bash
# Create
k create deployment webapp --image=nginx:1.26 --replicas=3

# Update image (triggers rolling update)
k set image deployment/webapp nginx=nginx:1.27

# Watch the rollout
k rollout status deployment/webapp

# Check history
k rollout history deployment/webapp

# Rollback to previous
k rollout undo deployment/webapp

# Rollback to specific revision
k rollout undo deployment/webapp --to-revision=2
```

Rolling update strategy options:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # max pods above desired count during update
      maxUnavailable: 0   # max pods that can be unavailable during update
```

- `maxSurge: 1, maxUnavailable: 0` = zero-downtime (one extra pod at a time)
- `maxSurge: 0, maxUnavailable: 1` = no extra pods, one goes down at a time
- `Recreate` strategy = kill all old pods first, then create new ones (causes downtime)

#### 3.2 — Use ConfigMaps and Secrets to Configure Applications

ConfigMaps hold non-sensitive config. Secrets hold sensitive data (base64-encoded, not encrypted by default).

```bash
# Create ConfigMap
k create configmap app-config \
  --from-literal=APP_MODE=production \
  --from-literal=LOG_LEVEL=info

# Create Secret
k create secret generic db-creds \
  --from-literal=DB_USER=admin \
  --from-literal=DB_PASS=changeme

# From file
k create configmap nginx-conf --from-file=nginx.conf
```

Three ways to inject into a pod:

**1. Environment variables (all keys):**
```yaml
envFrom:
- configMapRef:
    name: app-config
- secretRef:
    name: db-creds
```

**2. Single key as env var:**
```yaml
env:
- name: DATABASE_USER
  valueFrom:
    secretKeyRef:
      name: db-creds
      key: DB_USER
```

**3. Mounted as files:**
```yaml
volumeMounts:
- name: config-vol
  mountPath: /etc/config
volumes:
- name: config-vol
  configMap:
    name: app-config
```

Gotcha: if you mount a ConfigMap as a volume at a directory, it replaces the entire directory. Use `subPath` to mount a single file without replacing the directory.

#### 3.3 — Know How to Scale Applications

```bash
# Manual scaling
k scale deployment webapp --replicas=5

# Autoscaling (HPA — not heavily tested on CKA but know it exists)
k autoscale deployment webapp --min=2 --max=10 --cpu-percent=80
```

#### 3.4 — Self-Healing Workloads: Deployments, DaemonSets, StatefulSets

The one you'll actually use on the exam is **Deployment**. It manages ReplicaSets, which manage Pods. You create Deployments, you scale them, you update them, you roll them back. That's 90% of this topic.

- **ReplicaSet**: Keeps N pods running. You almost never create these directly — Deployments create them for you.
- **Deployment**: This is the workhorse. Rolling updates, rollbacks, scaling. Know this cold.
- **DaemonSet**: One pod per node. Logging agents, monitoring. Comes up occasionally on the exam. The YAML is basically a Deployment without `replicas`.
- **StatefulSet**: Stable network identity and persistent storage. Barely on the CKA — know it exists, maybe know the headless service pattern, don't spend hours on it.

```yaml
# DaemonSet — runs on every node
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: fluentd:v1.17
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

#### 3.5 — Understand How Resource Limits Can Affect Pod Scheduling

```yaml
resources:
  requests:
    memory: "64Mi"    # scheduler uses this to find a node
    cpu: "250m"       # 250 millicores = 0.25 CPU
  limits:
    memory: "128Mi"   # OOMKilled if exceeded
    cpu: "500m"       # throttled if exceeded
```

- **Requests** = what the scheduler looks at when placing the pod. If no node has enough, pod stays Pending.
- **Limits** = ceiling. Memory over limit = OOMKilled. CPU over limit = throttled.
- If you set limits without requests, requests default to limits.
- LimitRange sets defaults and constraints for a namespace. ResourceQuota caps total usage.

#### 3.6 — Awareness of Manifest Management and Common Templating Tools

On the CKA, you mostly write raw YAML. But know these exist:
- **Kustomize**: `k apply -k <dir>` — built into kubectl, overlays and patches
- **Helm**: package manager for Kubernetes — CKA may ask you to install a chart
- **kubectl $do**: generate YAML with `--dry-run=client -o yaml` and edit it

#### 3.7 — Schedule Pods on Specific Nodes

**nodeSelector** (simplest):
```yaml
spec:
  nodeSelector:
    disk: ssd
```

**Node affinity** (more flexible):
```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: disk
            operator: In
            values:
            - ssd
```

**Taints and tolerations:**

Taints go on nodes. Tolerations go on pods.

```bash
# Taint a node
k taint nodes node1 gpu=true:NoSchedule

# Remove taint
k taint nodes node1 gpu=true:NoSchedule-
```

```yaml
# Pod toleration
spec:
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

Effects:
- `NoSchedule` — don't schedule new pods (existing stay)
- `PreferNoSchedule` — try to avoid, but not strict
- `NoExecute` — evict existing pods too

#### 3.8 — Static Pods

Static pods are managed by the kubelet directly, not the API server. The kubelet watches a directory (usually `/etc/kubernetes/manifests/`) and creates pods from any YAML files it finds there.

```bash
# Find the static pod path
cat /var/lib/kubelet/config.yaml | grep staticPodPath
# Usually: /etc/kubernetes/manifests

# Create a static pod
sudo tee /etc/kubernetes/manifests/static-web.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: static-web
spec:
  containers:
  - name: web
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
```

Static pods show up in `kubectl get pods` with the node name appended (e.g., `static-web-node1`). You can't delete them via kubectl — the kubelet recreates them. To remove: delete the manifest file.

Control plane components (kube-apiserver, kube-scheduler, kube-controller-manager, etcd) are all static pods.

---

### Domain 4 — Cluster Architecture, Installation & Configuration (25%)

25% of the score. This is the domain that separates CKA from CKAD — etcd, kubeadm, RBAC. If you're coming from CKAD, this is all new and deserves the most study time. etcd backup/restore takes a while to get reliable, and the `--as=system:serviceaccount:ns:name` syntax for testing RBAC needs drilling until it is automatic.

> See also: [RBAC](questions/rbac-user-and-serviceaccount/) | [kubeadm Upgrade](questions/kubeadm-upgrade/) | [CRI-dockerd Setup](questions/cri-dockerd-setup/)

#### 4.1 — Manage Role-Based Access Control (RBAC)

RBAC has four objects:

| Object | Scope | Binds to |
|---|---|---|
| Role | Namespace | RoleBinding |
| ClusterRole | Cluster-wide | ClusterRoleBinding or RoleBinding |
| RoleBinding | Namespace | Role or ClusterRole |
| ClusterRoleBinding | Cluster-wide | ClusterRole |

```bash
# Create Role (namespace-scoped permissions)
k create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  -n dev

# Create RoleBinding
k create rolebinding read-pods \
  --role=pod-reader \
  --serviceaccount=dev:my-sa \
  -n dev

# Create ClusterRole (cluster-wide permissions)
k create clusterrole node-reader \
  --verb=get,list \
  --resource=nodes

# Create ClusterRoleBinding
k create clusterrolebinding read-nodes \
  --clusterrole=node-reader \
  --serviceaccount=dev:my-sa

# Test permissions
k auth can-i list pods -n dev --as=system:serviceaccount:dev:my-sa
k auth can-i list nodes --as=system:serviceaccount:dev:my-sa
```

Tricky bit: a ClusterRole bound with a RoleBinding only grants access in that namespace. A ClusterRole bound with a ClusterRoleBinding grants access cluster-wide. Same ClusterRole, different scope depending on the binding type.

#### 4.2 — Use Kubeadm to Install a Basic Cluster

The kubeadm workflow:

```bash
# On control plane node:
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (e.g., Calico)
k apply -f https://docs.projectcalico.org/manifests/calico.yaml

# On worker nodes:
sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

If you lost the join command:
```bash
kubeadm token create --print-join-command
```

#### 4.3 — Manage a Highly Available Kubernetes Cluster

You won't set up HA from scratch on the exam, but they want you to understand the two topologies:

- **Stacked etcd**: etcd on the same nodes as the control plane. This is what everyone uses. Simpler, good enough for most setups.
- **External etcd**: etcd on dedicated nodes. Rarely set up by hand; just know it exists and that it's "more resilient" because etcd failures don't take down the control plane node.
- Multiple control plane nodes behind a load balancer — the LB endpoint goes in `kubeadm init --control-plane-endpoint=<lb>:6443`

About 10 minutes on this topic is enough: read it, understand the difference, move on.

#### 4.4 — Provision Underlying Infrastructure to Deploy a Kubernetes Cluster

kubeadm handles most of this. You won't provision VMs on the exam, but you might need to fix a node that was set up wrong. The things that break:
- containerd not installed or not running — `systemctl status containerd`
- Swap still enabled — `swapoff -a` (easy to forget on fresh VMs)
- Missing kernel modules: `br_netfilter` and `overlay`. Load them with `modprobe`.
- sysctl params — `net.bridge.bridge-nf-call-iptables = 1`. Nobody remembers the exact name; grep the docs page.

#### 4.5 — Perform a Version Upgrade on a Kubernetes Cluster Using Kubeadm

This is a classic CKA question. The sequence matters:

**Control plane node:**
```bash
# 1. Update kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get update && sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm

# 2. Plan
sudo kubeadm upgrade plan

# 3. Apply
sudo kubeadm upgrade apply v1.35.0

# 4. Update kubelet + kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl

# 5. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

**Worker node:**
```bash
# 1. From control plane: drain the worker
k drain worker-1 --ignore-daemonsets --delete-emptydir-data

# 2. SSH to worker, update packages
sudo apt-mark unhold kubeadm kubelet kubectl
sudo apt-get update
sudo apt-get install -y kubeadm=1.35.0-1.1 kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubeadm kubelet kubectl

# 3. Upgrade node
sudo kubeadm upgrade node

# 4. Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 5. From control plane: uncordon
k uncordon worker-1
```

Key difference: control plane uses `kubeadm upgrade apply`, worker uses `kubeadm upgrade node`.

#### 4.6 — Implement etcd Backup and Restore

etcd backup and restore are part of cluster administration. Practice the commands and confirm the restored data rather than relying on memorized flags alone.

**Backup:**
```bash
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

Where to find the cert paths: `cat /etc/kubernetes/manifests/etcd.yaml` and look for `--cert-file`, `--key-file`, `--trusted-ca-file`.

**Verify:**
```bash
ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-table
```

**Restore:**
```bash
# 1. Restore to a new directory
ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored

# 2. Update etcd manifest to use the restored directory
sudo vi /etc/kubernetes/manifests/etcd.yaml
# Change --data-dir=/var/lib/etcd → --data-dir=/var/lib/etcd-restored
# Change hostPath path: /var/lib/etcd → /var/lib/etcd-restored

# 3. Wait for etcd to restart (it's a static pod)
# kubectl may be unresponsive for 30-60 seconds — that's normal
```

The three flags you need every time: `--cacert`, `--cert`, `--key`. Write them on the notepad in the exam environment before starting.

---

### Domain 5 — Services & Networking (20%)

20% of the score. Services, Ingress, Gateway API, NetworkPolicy, DNS. NetworkPolicy is where most points get lost — the AND vs OR selector behavior is unintuitive, and forgetting DNS egress is a silent killer.

> See also: [NetworkPolicy](questions/netpol-three-tier/) | [YAML templates](TEMPLATES.md)

#### 5.1 — Understand Host Networking Configuration on the Cluster Nodes

Networking in Kubernetes "just works" if your CNI is installed correctly. Don't overthink the model — pods get IPs, pods can talk to each other, nodes can talk to pods. The CNI plugin (Calico, Flannel, Cilium) makes it happen. That's really all you need to know conceptually.

What actually matters for the exam: knowing where to look when it doesn't work.

```bash
# Check what CNI is installed
ls /etc/cni/net.d/
cat /etc/cni/net.d/10-calico.conflist

# Check pod CIDR
k cluster-info dump | grep -m 1 cluster-cidr
```

#### 5.2 — Understand Connectivity Between Pods

Same-node pods talk through a bridge, cross-node pods go through the CNI overlay. You don't need to know the internals — but you need to test connectivity when something breaks.

```bash
# Test pod-to-pod connectivity
k exec pod-a -- wget -qO- --timeout=2 http://<pod-b-ip>

# Check pod IPs
k get pods -o wide
```

#### 5.3 — Understand ClusterIP, NodePort, LoadBalancer Service Types

| Type | How it works | When to use |
|---|---|---|
| **ClusterIP** | Internal cluster IP only | Internal services (default) |
| **NodePort** | ClusterIP + port on every node (30000-32767) | Dev/testing, direct node access |
| **LoadBalancer** | NodePort + cloud LB | Production with cloud provider |
| **ExternalName** | CNAME to external DNS | Pointing to external services |

```bash
# ClusterIP (default)
k expose deployment webapp --port=80 --target-port=8080

# NodePort (random port in 30000-32767)
k expose deployment webapp --port=80 --target-port=8080 --type=NodePort

# Specific NodePort — generate YAML, edit nodePort, then apply
k expose deployment webapp --port=80 --target-port=8080 --type=NodePort $do > svc.yaml
# edit svc.yaml → set spec.ports[0].nodePort: 30080
k apply -f svc.yaml
```

The most important thing: `port` is what clients use to reach the service. `targetPort` is the port the container listens on. `nodePort` is the port on the node (NodePort/LoadBalancer only).

#### 5.4 — Understand How to Use Ingress Controllers and Ingress Resources

Ingress gives you HTTP/HTTPS routing to services based on hostname or path.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
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

Requirements:
- An Ingress Controller must be installed (e.g., nginx-ingress). The Ingress resource alone does nothing.
- `ingressClassName` is required in v1.35 — the old annotation `kubernetes.io/ingress.class` still works but is deprecated.

#### 5.5 — Know How to Use and Configure CoreDNS

CoreDNS is the cluster DNS server (replaced kube-dns a long time ago). It runs as a Deployment in `kube-system`.

```bash
# Check CoreDNS pods
k get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS config
k get configmap coredns -n kube-system -o yaml

# Test DNS resolution
k run test-dns --image=busybox:1.36 --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

DNS naming:
- Service: `<service>.<namespace>.svc.cluster.local`
- Pod: `<pod-ip-dashed>.<namespace>.pod.cluster.local`

If DNS doesn't work:
1. Is CoreDNS running? `k get pods -n kube-system -l k8s-app=kube-dns`
2. Does kube-dns service have endpoints? `k get endpoints kube-dns -n kube-system`
3. Is the Corefile correct? `k get cm coredns -n kube-system -o yaml`
4. Can the pod reach the DNS service? `k exec <pod> -- cat /etc/resolv.conf`

#### 5.6 — Choose an Appropriate Container Network Interface Plugin

The CKA won't ask you to write a CNI plugin. Just use Calico. It supports NetworkPolicy, it's the most common, and it's what most training platforms use. The exam doesn't care which CNI is installed.

Other CNIs exist — Flannel is simpler but doesn't support NetworkPolicy (dealbreaker for the exam), Cilium is the fancy eBPF one everyone's talking about, Weave still works. But if a question says "install a CNI plugin," just apply the Calico manifest and move on.

Install is one `kubectl apply -f <url>`. The CNI must be installed before worker nodes join — pods stay Pending without it.

#### 5.7 — Understand NetworkPolicy

NetworkPolicy controls pod-to-pod traffic. Once you apply any NetworkPolicy to a pod, all traffic not explicitly allowed is denied for that pod.

```yaml
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

Critical gotcha on the exam: if you add an Egress policy, you must also allow DNS (UDP 53). Otherwise the pod can't resolve any service names and everything looks broken even though the policy is "correct."

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

This difference trips up a lot of people. Read the indentation carefully.

#### 5.8 — Gateway API

Gateway API provides resources for configuring service traffic. Which resources work depends on the Gateway API version and controller installed in the cluster. The current CKA curriculum includes Gateway API; consult that curriculum and the relevant controller documentation for scope and setup.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
spec:
  parentRefs:
  - name: my-gateway
  hostnames:
  - "myapp.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: api-service
      port: 80
```

Key differences from Ingress:
- Gateway = infrastructure resource (managed by platform team)
- HTTPRoute = application routing (managed by app team)
- More features: header matching, traffic splitting, request mirroring
- Supports TCP, UDP, gRPC — not just HTTP

---

## CKA Domain Weight Distribution

```mermaid
pie title CKA Exam Domain Weights
    "Troubleshooting (30%)" : 30
    "Cluster Architecture (25%)" : 25
    "Services & Networking (20%)" : 20
    "Workloads & Scheduling (15%)" : 15
    "Storage (10%)" : 10
```

Where to focus: Troubleshooting + Cluster Architecture = 55% of the exam. If you nail these two, you only need a few more points to pass.

---

## Exam Day Strategy — Time Allocation

A two-pass approach makes a big difference. Without it, it is easy to get stuck on a hard question for 12 minutes and run out of time for easy ones worth the same points.

**Pass 1 (first 80 minutes):** Do all questions in order. If a question looks like it'll take more than 8 minutes, flag it and move on. Don't get emotionally invested in any single question.

**Pass 2 (last 40 minutes):** Go back to flagged questions. You now know exactly how much time you have. The pressure feels different when you've already banked easy points.

Time estimates by question type:

| Question Type | Typical Time | Notes |
|---|---|---|
| Create a pod/deployment | 2-3 min | Use `$do` to generate YAML |
| Create RBAC resources | 3-5 min | Know the imperative commands |
| NetworkPolicy | 5-8 min | Always allow DNS egress |
| etcd backup/restore | 8-10 min | Know the cert paths |
| kubeadm upgrade | 8-10 min | Follow the sequence exactly |
| Troubleshoot broken node | 5-8 min | Check kubelet first |
| Troubleshoot networking | 5-8 min | Check endpoints, selectors |
| PV/PVC/StorageClass | 4-6 min | Match accessModes and storageClassName |
| DaemonSet | 3-4 min | Copy from docs fast |
| Ingress/Gateway | 4-6 min | Know ingressClassName |
| Static pod | 3-4 min | Write manifest directly to /etc/kubernetes/manifests/ |
| Node drain/cordon | 2-3 min | --ignore-daemonsets --delete-emptydir-data |

Total available: 120 minutes. Budget ~100 minutes for questions, 20 minutes buffer for context switching, copy/paste fumbling, and double-checking.

[Back to top](#table-of-contents)

---

## Mistakes That Will Fail You on the CKA

These are not hypothetical risks — they are the mistakes that cost points most often in practice exams.

### 1. Forgetting to switch context

Every question says "use context k8s-xxx." Missing it means two perfect answers on the wrong cluster — zero points for both. Read the context line first, switch, then read the actual question.

```bash
# ALWAYS do this first
k config use-context <context-name>
```

### 2. Wrong namespace

A perfect Deployment in `default` when the question said `production` scores zero: the grader checks the namespace. Run `kn <namespace>` as the FIRST command for every question.

```bash
# Set namespace for the question
kn <namespace>
# Or use -n on every command
k get pods -n production
```

### 3. YAML indentation errors

One tab character hidden in a YAML file makes `kubectl apply` fail with a cryptic parsing error that can take minutes to find. Set up vim with `expandtab` so tabs become spaces. One wrong indent level = broken YAML = zero points.

```bash
# This should already be in your .vimrc
set expandtab
set tabstop=2
set shiftwidth=2
```

### 4. etcd restore — forgetting to update hostPath

A classic: etcd is restored to `/var/lib/etcd-restored` and the `--data-dir` flag is updated. The cluster comes back, but all previous resources are gone, because the `hostPath.path` in the volume section still points to the old `/var/lib/etcd`. The etcd process and the volume mount have to agree, or you're reading from the wrong directory.

```yaml
# Must update BOTH:
# 1. --data-dir=/var/lib/etcd-restored
# 2. volumes[].hostPath.path: /var/lib/etcd-restored
```

### 5. Drain without --ignore-daemonsets

`k drain` fails if DaemonSet pods exist and you don't pass the flag. Don't waste time reading the error — just always use:

```bash
k drain <node> --ignore-daemonsets --delete-emptydir-data
```

### 6. NetworkPolicy without DNS egress

A classic. You write what looks like a perfect NetworkPolicy egress rule, test connectivity, and it fails. You rewrite the rule. Still fails. You check selectors. Still right. The pod can't resolve service names because you didn't allow UDP 53. Write the DNS egress block FIRST, before any other egress rules.

```yaml
# Always include this in egress rules
- to: []
  ports:
  - protocol: UDP
    port: 53
```

### 7. Not verifying your work

Finishing a question early and moving on feels great until the pod turns out to be in `ImagePullBackOff` because of a typo in the image name. `k get pod` would have caught it in 5 seconds. Verify every resource you create before moving on.

```bash
k get pod <name> -n <ns>        # Is it Running?
k get svc <name> -n <ns>        # Does service exist?
k get endpoints <name> -n <ns>  # Does service have endpoints?
```

### 8. Wasting time on hard questions first

A 3-point question and a 7-point question get the same time if you're stuck. Do the easy ones first.

### 9. Forgetting the ServiceAccount in RBAC

The question says "create a ServiceAccount and give it access." Jumping straight to the Role and RoleBinding, `k auth can-i` returns "no" for everything — and it takes minutes to realize the ServiceAccount doesn't exist. The RoleBinding referenced a SA that wasn't there. Create the SA first.

```bash
# Create SA first
k create sa my-sa -n my-ns

# Then bind it
k create rolebinding my-binding \
  --role=my-role \
  --serviceaccount=my-ns:my-sa \
  -n my-ns
```

---

## Vim Keys You Need on Exam Day

Not a vim guide, just the handful you keep hitting. If you already know vim, skip this.

Vim has two modes that matter here: **insert mode** (where you type text like a normal editor) and **normal mode** (where keys are commands). You start in normal mode. Press `i` to enter insert mode, press `Esc` to get back to normal mode. Almost every shortcut below is a normal mode command, so hit `Esc` first if you are not sure where you are.

**Opening and saving**

- `vim <file>` to open the file. You start in normal mode.
- `i` (normal mode) to enter insert mode and start typing.
- `Esc` to leave insert mode and go back to normal mode.
- `:wq` (normal mode) to save and quit. `:q!` to bail without saving.

**Moving around (normal mode)**

- `A` jumps to the end of the current line and drops you into insert mode. Handy for adding to an existing line without arrow-keying across.
- `$` moves the cursor to the end of the line without entering insert mode.
- `0` moves to the start of the line.
- `gg` jumps to the top of the file, `G` jumps to the bottom.
- `H` top of the visible screen, `M` middle, `L` bottom.
- `/word` then `Enter` to search, `n` for the next match.

**Editing (normal mode)**

- `<number>dd` deletes that many lines. `5dd` wipes 5 lines at once. Handy for cleaning up the junk that `kubectl ... --dry-run=client -o yaml` adds (status blocks, creationTimestamp, empty resources).
- `dd` on its own deletes the current line.
- `u` to undo.

That is all you need. Anything fancier can be looked up, but it rarely comes up.

[Back to top](#table-of-contents)


---

## Troubleshooting Decision Flowchart

Use this when something is broken and you don't know where to start.

```mermaid
flowchart TD
    START[Something is broken] --> NODES{Are all nodes Ready?}
    
    NODES -->|No| NODE_DEBUG[Node is NotReady]
    NODE_DEBUG --> KUBELET{Is kubelet running?}
    KUBELET -->|No| KUBELET_FIX[systemctl start kubelet<br/>Check journalctl -u kubelet]
    KUBELET -->|Yes| CERTS{Are certs expired?}
    CERTS -->|Yes| CERT_FIX[kubeadm certs renew all]
    CERTS -->|No| NET{Node networking OK?}
    NET -->|No| NET_FIX[Check CNI plugin<br/>Check kube-proxy]
    
    NODES -->|Yes| PODS{Is the pod running?}
    
    PODS -->|Pending| PENDING[Check describe pod events]
    PENDING --> PEND_RES{Resource issue?}
    PEND_RES -->|Yes| RES_FIX[Scale down or add nodes]
    PEND_RES -->|No| PEND_SCHED{Scheduling issue?}
    PEND_SCHED -->|Taint| TAINT_FIX[Add toleration or remove taint]
    PEND_SCHED -->|Selector| SEL_FIX[Fix nodeSelector or affinity]
    PEND_SCHED -->|PVC| PVC_FIX[Fix PVC — check storageClass, accessMode]
    
    PODS -->|CrashLoop| CRASH[Check logs --previous]
    CRASH --> CRASH_CMD{Wrong command?}
    CRASH_CMD -->|Yes| CMD_FIX[Fix command/args]
    CRASH_CMD -->|No| CRASH_CFG{Missing config?}
    CRASH_CFG -->|Yes| CFG_FIX[Fix ConfigMap/Secret/env]
    CRASH_CFG -->|No| APP_FIX[Application bug — check logs]
    
    PODS -->|ImagePull| IMAGE[Check image name/tag]
    IMAGE --> IMG_SECRET{Private registry?}
    IMG_SECRET -->|Yes| SECRET_FIX[Add imagePullSecrets]
    IMG_SECRET -->|No| IMG_FIX[Fix image name or check network]
    
    PODS -->|Running| SVC{Can you reach the service?}
    SVC -->|No| EP{Service has endpoints?}
    EP -->|No| LABEL_FIX[Fix selector — labels don't match]
    EP -->|Yes| PORT{targetPort matches container?}
    PORT -->|No| PORT_FIX[Fix targetPort]
    PORT -->|Yes| DNS{DNS resolving?}
    DNS -->|No| DNS_FIX[Check CoreDNS pods + configmap]
    DNS -->|Yes| NETPOL{NetworkPolicy blocking?}
    NETPOL -->|Yes| NP_FIX[Fix NetworkPolicy rules]
    
    PODS -->|Running| ETCD{etcd healthy?}
    ETCD -->|No| ETCD_FIX[Check etcd pod<br/>Restore from backup if needed]
```

---

## Practice Scenarios with Full Solutions

These are longer, multi-step scenarios that mimic real exam questions.

### Scenario 1: etcd Backup and Restore

**Task:** Back up etcd to `/opt/etcd-backup.db`, then restore it to verify the backup works.

<details>
<summary>Solution</summary>

```bash
# Find cert paths
grep -E "cert-file|key-file|trusted-ca-file" /etc/kubernetes/manifests/etcd.yaml

# Backup
ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db --write-table

# Restore
ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored

# Update etcd manifest
sudo vi /etc/kubernetes/manifests/etcd.yaml
# Change --data-dir=/var/lib/etcd → --data-dir=/var/lib/etcd-restored
# Change hostPath path: /var/lib/etcd → /var/lib/etcd-restored

# Wait for etcd to restart
# kubectl may hang for 30-60s — that's normal
sleep 30
k get nodes
```

</details>

### Scenario 2: RBAC — ServiceAccount with Limited Access

**Task:** In namespace `dev`, create a ServiceAccount `deploy-bot` that can only create and list Deployments. Verify it cannot delete pods.

<details>
<summary>Solution</summary>

```bash
k create ns dev
k create sa deploy-bot -n dev
k create role deploy-manager -n dev \
  --verb=create,list,get \
  --resource=deployments
k create rolebinding deploy-bot-binding -n dev \
  --role=deploy-manager \
  --serviceaccount=dev:deploy-bot

# Verify
k auth can-i create deployments -n dev --as=system:serviceaccount:dev:deploy-bot
# yes
k auth can-i delete pods -n dev --as=system:serviceaccount:dev:deploy-bot
# no
```

</details>

### Scenario 3: Node Drain and Maintenance

**Task:** Drain node `worker-2` for maintenance, verify pods are rescheduled, then bring it back.

<details>
<summary>Solution</summary>

```bash
# Check current state
k get pods -o wide | grep worker-2

# Drain
k drain worker-2 --ignore-daemonsets --delete-emptydir-data

# Verify node is cordoned
k get nodes
# worker-2 should show SchedulingDisabled

# Verify pods moved
k get pods -o wide
# No non-DaemonSet pods on worker-2

# Simulate maintenance (wait)
# ...

# Bring back
k uncordon worker-2
k get nodes
# worker-2 should be Ready
```

</details>

### Scenario 4: kubeadm Upgrade

**Task:** Upgrade the control plane from Kubernetes v1.34.x to v1.35.0.

<details>
<summary>Solution</summary>

```bash
# 1. Upgrade kubeadm
sudo apt-mark unhold kubeadm
sudo apt-get update
sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm

# 2. Plan
sudo kubeadm upgrade plan

# 3. Apply
sudo kubeadm upgrade apply v1.35.0

# 4. Upgrade kubelet + kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl

# 5. Restart
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# 6. Verify
k get nodes
```

</details>

### Scenario 5: Troubleshoot — Pod Can't Reach Service

**Task:** Pod `client` can't reach service `backend-svc` on port 80. Find and fix the issue.

<details>
<summary>Solution</summary>

```bash
# 1. Check service exists
k get svc backend-svc

# 2. Check endpoints
k get endpoints backend-svc
# If empty: selector doesn't match!

# 3. Check service selector
k describe svc backend-svc | grep Selector
# e.g., Selector: app=backend

# 4. Check pod labels
k get pods --show-labels | grep backend
# e.g., labels are app=back (typo!)

# 5. Fix pod labels
k label pod <backend-pod> app=backend --overwrite

# 6. Or fix service selector
k edit svc backend-svc
# Change selector to match actual pod labels

# 7. Verify
k get endpoints backend-svc
# Should now show pod IPs
k exec client -- wget -qO- --timeout=2 http://backend-svc
```

</details>

### Scenario 6: NetworkPolicy — Isolate Database

**Task:** Create a NetworkPolicy that allows only pods with label `role=api` to reach pods with label `role=db` on port 5432. Block all other ingress to the database.

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-isolation
spec:
  podSelector:
    matchLabels:
      role: db
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: api
    ports:
    - protocol: TCP
      port: 5432
```

```bash
k apply -f db-policy.yaml

# Test — api pod should work
k exec api-pod -- nc -zv <db-pod-ip> 5432

# Test — other pod should fail
k exec other-pod -- nc -zv <db-pod-ip> 5432
```

</details>

### Scenario 7: PV/PVC — Persistent Storage

**Task:** Create a PV using hostPath `/data/logs` (1Gi, ReadWriteOnce, Retain), a PVC requesting 500Mi, and mount it in a pod at `/var/log/app`.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: log-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /data/logs
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: log-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
  storageClassName: manual
---
apiVersion: v1
kind: Pod
metadata:
  name: log-pod
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo $(date) >> /var/log/app/app.log; sleep 5; done"]
    volumeMounts:
    - name: log-vol
      mountPath: /var/log/app
  volumes:
  - name: log-vol
    persistentVolumeClaim:
      claimName: log-pvc
```

```bash
k apply -f storage.yaml
k get pv log-pv
k get pvc log-pvc
k exec log-pod -- cat /var/log/app/app.log
```

</details>

### Scenario 8: Sidecar Container — Log Streaming

**Task:** Create a pod with a main container writing logs to `/var/log/app.log` and a sidecar (native v1.35 style) streaming that file to stdout.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-logging
spec:
  initContainers:
  - name: log-streamer
    image: busybox:1.36
    restartPolicy: Always
    command: ["sh", "-c", "tail -f /var/log/app.log"]
    volumeMounts:
    - name: log-vol
      mountPath: /var/log
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date) app running\" >> /var/log/app.log; sleep 3; done"]
    volumeMounts:
    - name: log-vol
      mountPath: /var/log
  volumes:
  - name: log-vol
    emptyDir: {}
```

```bash
k apply -f sidecar.yaml
k logs sidecar-logging -c log-streamer
```

</details>

---

## Practice Questions with Answers (Mock Exam)

17 original practice questions, with weights assigned for this worksheet. They are not official exam questions, and their weights do not represent published CKA question weights. Switch context before each one.

---

### Question 1 [4%] [Cluster Architecture] Easy

`kubectl config use-context k8s-cluster1`

Create a ServiceAccount named `monitoring-sa` in namespace `monitoring`. Create a ClusterRole named `pod-viewer` that can `get`, `list`, `watch` pods in all namespaces. Bind the ClusterRole to the ServiceAccount.

<details>
<summary>Solution</summary>

```bash
k create ns monitoring
k create sa monitoring-sa -n monitoring
k create clusterrole pod-viewer --verb=get,list,watch --resource=pods
k create clusterrolebinding pod-viewer-binding \
  --clusterrole=pod-viewer \
  --serviceaccount=monitoring:monitoring-sa

# Verify
k auth can-i list pods -A --as=system:serviceaccount:monitoring:monitoring-sa
```

</details>

---

### Question 2 [5%] [Cluster Architecture] Medium

`kubectl config use-context k8s-cluster1`

Back up etcd to `/opt/etcd-snapshot.db`. The etcd server is running on the control plane node at `https://127.0.0.1:2379`.

<details>
<summary>Solution</summary>

```bash
# Find cert paths
cat /etc/kubernetes/manifests/etcd.yaml | grep -E "cert-file|key-file|trusted-ca"

ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-snapshot.db --write-table
```

</details>

---

### Question 3 [3%] [Workloads & Scheduling] Easy

`kubectl config use-context k8s-cluster2`

Create a Deployment named `web-app` in namespace `production` with 3 replicas using image `nginx:1.27`. Expose it as a ClusterIP service named `web-svc` on port 80.

<details>
<summary>Solution</summary>

```bash
k create ns production
k create deployment web-app -n production --image=nginx:1.27 --replicas=3
k expose deployment web-app -n production --port=80 --target-port=80 --name=web-svc
k get deploy,svc -n production
```

</details>

---

### Question 4 [5%] [Troubleshooting] Medium

`kubectl config use-context k8s-cluster1`

Node `worker-1` is showing `NotReady`. Investigate and fix the issue so the node becomes `Ready`.

<details>
<summary>Solution</summary>

```bash
# Check node status
k describe node worker-1 | grep -A5 Conditions

# SSH to the node
ssh worker-1

# Check kubelet
sudo systemctl status kubelet
# If inactive/dead:
sudo systemctl start kubelet
sudo systemctl enable kubelet

# If it's a config issue, check logs
sudo journalctl -u kubelet --no-pager | tail -30

# Common fixes:
# - Wrong --kubeconfig path
# - Certificate issue → check /var/lib/kubelet/config.yaml
# - Swap enabled → sudo swapoff -a

# Verify from control plane
k get nodes
```

</details>

---

### Question 5 [4%] [Services & Networking] Medium

`kubectl config use-context k8s-cluster2`

Create a NetworkPolicy named `restrict-ingress` in namespace `production` that:
- Applies to pods with label `app=database`
- Allows ingress only from pods with label `app=backend` on TCP port 3306
- Allows DNS egress (UDP 53)

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-ingress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 3306
  egress:
  - to: []
    ports:
    - protocol: UDP
      port: 53
```

```bash
k apply -f netpol.yaml
```

</details>

---

### Question 6 [5%] [Cluster Architecture] Medium

`kubectl config use-context k8s-cluster1`

Upgrade the control plane node from Kubernetes v1.34.4 to v1.35.0 using kubeadm.

<details>
<summary>Solution</summary>

```bash
sudo apt-mark unhold kubeadm
sudo apt-get update
sudo apt-get install -y kubeadm=1.35.0-1.1
sudo apt-mark hold kubeadm

sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.35.0

sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.35.0-1.1 kubectl=1.35.0-1.1
sudo apt-mark hold kubelet kubectl

sudo systemctl daemon-reload
sudo systemctl restart kubelet

k get nodes
```

</details>

---

### Question 7 [3%] [Storage] Easy

`kubectl config use-context k8s-cluster2`

Create a PersistentVolume named `data-pv` with 2Gi capacity, ReadWriteOnce access, hostPath `/data/volumes/pv1`, and storageClassName `manual`. Create a PersistentVolumeClaim named `data-pvc` in namespace `storage-test` requesting 1Gi.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: data-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  storageClassName: manual
  hostPath:
    path: /data/volumes/pv1
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage-test
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: manual
```

```bash
k create ns storage-test
k apply -f storage.yaml
k get pv data-pv
k get pvc data-pvc -n storage-test
```

</details>

---

### Question 8 [5%] [Troubleshooting] Hard

`kubectl config use-context k8s-cluster1`

Service `frontend-svc` in namespace `web` has no endpoints. Pods with label `app=frontend` are running. Find and fix the issue.

<details>
<summary>Solution</summary>

```bash
# 1. Check service
k describe svc frontend-svc -n web | grep Selector
# e.g., Selector: app=front (typo)

# 2. Check pod labels
k get pods -n web --show-labels
# Labels show: app=frontend

# 5. Fix pod labels
k label pod <backend-pod> app=backend --overwrite

# 6. Or fix service selector
k edit svc frontend-svc
# Change selector to match actual pod labels

# 7. Verify
k get endpoints frontend-svc -n web
```

</details>

---

### Question 9 [4%] [Workloads & Scheduling] Medium

`kubectl config use-context k8s-cluster2`

Create a DaemonSet named `log-collector` in namespace `kube-system` using image `fluentd:v1.17`. It should run on all nodes including the control plane.

<details>
<summary>Solution</summary>

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: log-collector
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: fluentd
        image: fluentd:v1.17
```

```bash
k apply -f ds.yaml
k get ds log-collector -n kube-system
k get pods -n kube-system -l app=log-collector -o wide
# Should run on ALL nodes
```

</details>

---

### Question 10 [5%] [Troubleshooting] Hard

`kubectl config use-context k8s-cluster1`

DNS resolution is not working in the cluster. Pods cannot resolve service names. Find and fix the issue.

<details>
<summary>Solution</summary>

```bash
# 1. Check CoreDNS pods
k get pods -n kube-system -l k8s-app=kube-dns
# Are they running? CrashLoopBackOff?

# 2. If not running, check logs
k logs -n kube-system -l k8s-app=kube-dns

# 3. Check CoreDNS ConfigMap
k get cm coredns -n kube-system -o yaml
# Look for syntax errors in Corefile

# 4. Check kube-dns service
k get svc kube-dns -n kube-system
k get endpoints kube-dns -n kube-system

# 5. Common fixes:
# - Corefile syntax error → fix ConfigMap, pods restart automatically
# - CoreDNS pods not scheduled → check tolerations
# - kube-dns service missing → recreate it

# 6. Test
k run test-dns --image=busybox:1.36 --rm -it -- nslookup kubernetes.default.svc.cluster.local
```

</details>

---

### Question 11 [3%] [Workloads & Scheduling] Easy

`kubectl config use-context k8s-cluster2`

Create a static pod named `static-nginx` on node `worker-1` using image `nginx:1.27` with port 80.

<details>
<summary>Solution</summary>

```bash
# SSH to worker-1
ssh worker-1

# Create manifest
sudo tee /etc/kubernetes/manifests/static-nginx.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF

# Back on control plane
k get pods | grep static-nginx
```

</details>

---

### Question 12 [4%] [Cluster Architecture] Medium

`kubectl config use-context k8s-cluster1`

Drain node `worker-2` for maintenance. Make sure no pods are disrupted unexpectedly. After a simulated maintenance window, make the node schedulable again.

<details>
<summary>Solution</summary>

```bash
k drain worker-2 --ignore-daemonsets --delete-emptydir-data

# Verify
k get nodes
# worker-2: SchedulingDisabled
k get pods -o wide | grep worker-2
# Only DaemonSet pods

# After maintenance
k uncordon worker-2
k get nodes
# worker-2: Ready
```

</details>

---

### Question 13 [5%] [Services & Networking] Medium

`kubectl config use-context k8s-cluster2`

Create an Ingress resource named `app-ingress` in namespace `web` that routes:
- `app.example.com/api` to service `api-svc` on port 8080
- `app.example.com/web` to service `web-svc` on port 80

Use ingressClassName `nginx`.

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 8080
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
```

```bash
k apply -f ingress.yaml
k get ingress app-ingress -n web
```

</details>

---

### Question 14 [5%] [Troubleshooting] Hard

`kubectl config use-context k8s-cluster1`

A pod named `failing-app` in namespace `debug` is in `CrashLoopBackOff`. Investigate and fix it.

<details>
<summary>Solution</summary>

```bash
# 1. Check events
k describe pod failing-app -n debug

# 2. Check logs (previous container)
k logs failing-app -n debug --previous

# 3. Common issues:
# a) Wrong command → fix command/args
# b) Missing ConfigMap/Secret → create the missing resource
# c) Wrong env var reference → fix valueFrom
# d) Application crash → fix the image or config

# 4. Fix based on what you find, e.g.:
k edit pod failing-app -n debug
# Or delete and recreate with fixes:
k get pod failing-app -n debug -o yaml > fix.yaml
# Edit fix.yaml
k delete pod failing-app -n debug $now
k apply -f fix.yaml

# 5. Verify
k get pod failing-app -n debug
# Should be Running
```

</details>

---

### Question 15 [4%] [Storage] Medium

`kubectl config use-context k8s-cluster2`

Create a pod named `volume-pod` in namespace `storage-test` that mounts the existing PVC `data-pvc` at `/data`. Write the string "exam-test" to `/data/test.txt`. Verify the file exists.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-pod
  namespace: storage-test
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "echo 'exam-test' > /data/test.txt && sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```

```bash
k apply -f pod.yaml
k exec volume-pod -n storage-test -- cat /data/test.txt
# Should output: exam-test
```

</details>

---

### Question 16 [5%] [Cluster Architecture] Hard

`kubectl config use-context k8s-cluster1`

Restore etcd from the snapshot at `/opt/etcd-snapshot.db`. Restore it to data directory `/var/lib/etcd-from-backup`.

<details>
<summary>Solution</summary>

```bash
# Restore
ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-from-backup

# Update etcd manifest
sudo vi /etc/kubernetes/manifests/etcd.yaml
# 1. Change --data-dir=/var/lib/etcd to --data-dir=/var/lib/etcd-from-backup
# 2. In volumes section, change hostPath path from /var/lib/etcd to /var/lib/etcd-from-backup

# Wait for etcd to restart
# kubectl may hang for 30-60s — that's normal
sleep 30
k get nodes
```

</details>

---

### Question 17 [4%] [Workloads & Scheduling] Medium

`kubectl config use-context k8s-cluster2`

Create a pod named `restricted-pod` in namespace `secure` that:
- Uses image `nginx:1.27`
- Runs as user ID 1000
- Has a read-only root filesystem
- Drops all capabilities
- Does not allow privilege escalation

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
  namespace: secure
spec:
  securityContext:
    runAsUser: 1000
  containers:
  - name: nginx
    image: nginx:1.27
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
```

```bash
k create ns secure
k apply -f restricted.yaml
k get pod restricted-pod -n secure
```

</details>

---

### Score Card

Copy this table into a text file. After completing the mock, mark each question as full credit, partial, or missed. Add up your weighted score.

| # | Domain | Weight | Difficulty | Result | Points |
|---|---|---|---|---|---|
| 1 | Cluster Architecture | 4% | Easy | ___ | /4 |
| 2 | Cluster Architecture | 5% | Medium | ___ | /5 |
| 3 | Workloads & Scheduling | 3% | Easy | ___ | /3 |
| 4 | Troubleshooting | 5% | Medium | ___ | /5 |
| 5 | Services & Networking | 4% | Medium | ___ | /4 |
| 6 | Cluster Architecture | 5% | Medium | ___ | /5 |
| 7 | Storage | 3% | Easy | ___ | /3 |
| 8 | Troubleshooting | 5% | Hard | ___ | /5 |
| 9 | Workloads & Scheduling | 4% | Medium | ___ | /4 |
| 10 | Troubleshooting | 5% | Hard | ___ | /5 |
| 11 | Workloads & Scheduling | 3% | Easy | ___ | /3 |
| 12 | Cluster Architecture | 4% | Medium | ___ | /4 |
| 13 | Services & Networking | 5% | Medium | ___ | /5 |
| 14 | Troubleshooting | 5% | Hard | ___ | /5 |
| 15 | Storage | 4% | Medium | ___ | /4 |
| 16 | Cluster Architecture | 5% | Hard | ___ | /5 |
| 17 | Workloads & Scheduling | 4% | Medium | ___ | /4 |
| | **Total** | **73%** | | | **___/73** |

**How to score:** Full credit = full weight. Partial (got the right idea but missed a flag or namespace) = half weight. Wrong or skipped = 0. Real exam uses partial scoring too, so this is realistic.

**Passing threshold:** 66% of 73 = **48 points**. If you're below 48, re-study the domains where you dropped points and redo those questions in a week.

**Timing target:** Set a timer for 2 hours. If you finish early, note how much time you had left — that buffer is your safety margin on exam day.

**Domain breakdown of this mock:**

| Domain | Questions | Total Weight | Your Score |
|---|---|---|---|
| Cluster Architecture | 1, 2, 6, 12, 16 | 23% | ___/23 |
| Troubleshooting | 4, 8, 10, 14 | 20% | ___/20 |
| Services & Networking | 5, 13 | 9% | ___/9 |
| Workloads & Scheduling | 3, 9, 11, 17 | 14% | ___/14 |
| Storage | 7, 15 | 7% | ___/7 |

If any domain is below 50%, that's where your next study session should focus.

[Back to top](#table-of-contents)

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
- Configure aliases and vim ([exam-setup.sh](scripts/exam-setup.sh))
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

- Take [mock exams](#mock-exams--final-preparation) with `./cka` under timed conditions (2 hours)
- Review killer.sh results — identify weak areas
- Redo the questions you failed (`./cka` puts them first)
- Practice context switching discipline — every question, switch context first
- Do killer.sh session 2 (3 days before exam)

### Week 5 (Optional) — Polish

- Only if you didn't feel ready after Week 4
- Focus entirely on weak domains
- Practice speed: can you do a full RBAC setup in under 3 minutes?
- Review the [mistakes list](#mistakes-that-will-fail-you-on-the-cka) one more time
- A buffer week, just in case

---

## killer.sh vs the Real CKA Exam

How killer.sh compares with the real exam:

| | **killer.sh** | **Real CKA Exam** |
|---|---|---|
| **Difficulty** | Harder — deliberately over-tests | Moderate |
| **Task count** | Varies by session | The Linux Foundation does not publish a fixed count |
| **Time pressure** | Very tight — most people don't finish | Tight but doable |
| **Question length** | Some are multi-step and long | More focused, but some still tricky |
| **Scoring** | Shows score after 24h session | Shows score in 24h via email |
| **Environment** | Same PSI-like terminal | PSI Secure Browser |
| **kubectl access** | Same as real exam | Same |
| **Docs access** | kubernetes.io | kubernetes.io |
| **Gotchas** | Design to fail you | Fewer gotchas, but present |

If you score 60%+ on killer.sh, you'll likely pass the real exam. Note: killer.sh is harder overall, but the real exam has its own tricky questions. Don't underestimate the actual exam — stay focused on every question, not just the complex ones.

[Back to top](#table-of-contents)

---

## CKA Exam Day Checklist

### 1 Week Before

- [ ] Schedule the exam — pick a time when you're sharpest, not Friday evening after a long week
- [ ] Verify your CNCF account name matches your government ID EXACTLY — character for character, including middle name if it's on your ID
- [ ] Do killer.sh session 2
- [ ] Review your weakest domain one more time (`./cka` statistics show it)
- [ ] Test your webcam, microphone, and internet — the PSI system check catches issues early

### 1 Day Before

- [ ] Clear your desk completely — nothing on it except laptop, keyboard, mouse. Sticky notes on the monitor have to go too.
- [ ] Remove second monitors, disconnect external screens
- [ ] Switch to wired ethernet if possible — a WiFi drop costs minutes of reconnecting
- [ ] Run through the [first 60 seconds setup](#first-60-seconds--aliases-vim-bash) from memory one last time
- [ ] Read the [exam day strategy](#exam-day-strategy--time-allocation) but don't cram new content — it won't stick
- [ ] Sleep. Seriously. It helps more than any last-minute studying.

### 30 Minutes Before

- [ ] Close every app except the PSI browser — it checks for background processes
- [ ] Go to the bathroom. You can't pause the exam.
- [ ] Have water ready in a clear bottle with no label (they make you peel it off if it has one)
- [ ] Start PSI check-in 15 minutes early — the room scan and ID verification take longer than you expect
- [ ] Show the proctor your desk, under your desk, and your walls

### During the Exam

- [ ] Type your aliases and vim config FIRST — before even reading question 1
- [ ] Switch context before every question — answers in the wrong context score zero
- [ ] Read the full question before touching the terminal. Misreading means solving the wrong problem.
- [ ] Flag anything that looks like it'll take >8 minutes. Come back after you've scored the easy points.
- [ ] Verify everything: `k get`, `k describe`, check the namespace
- [ ] If kubectl hangs after etcd restore, WAIT. It comes back in 30-60 seconds. Don't start editing the manifest again.

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
- [ ] Complete [static-pv-rwx](questions/static-pv-rwx/)

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
- [ ] Complete [cluster-multi-fault](questions/cluster-multi-fault/), [kubectl-debug-pod-node](questions/kubectl-debug-pod-node/)

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
- [ ] Complete [pod-labels-resources](questions/pod-labels-resources/), [rollout-rollback](questions/rollout-rollback/), [static-pod](questions/static-pod/), [hpa-cpu-autoscaling](questions/hpa-cpu-autoscaling/)

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
- [ ] Complete [rbac-user-and-serviceaccount](questions/rbac-user-and-serviceaccount/), [node-drain-maintenance](questions/node-drain-maintenance/), [kubeadm-upgrade](questions/kubeadm-upgrade/), [helm-upgrade-rollback](questions/helm-upgrade-rollback/), [kustomize-base-overlay](questions/kustomize-base-overlay/), [cri-dockerd-setup](questions/cri-dockerd-setup/), [pss-fix-deployment](questions/pss-fix-deployment/)

### Domain 5 — Services & Networking (20%)

- [ ] ClusterIP, NodePort, LoadBalancer services
- [ ] Classic Ingress resources and path-based routing
- [ ] Ingress TLS termination and IngressClass
- [ ] Gateway API (Gateway + HTTPRoute)
- [ ] NetworkPolicy (ingress + egress)
- [ ] CoreDNS configuration
- [ ] CNI plugin awareness
- [ ] Complete [netpol-three-tier](questions/netpol-three-tier/), [gateway-traffic-split](questions/gateway-traffic-split/), [ingress-tls-paths](questions/ingress-tls-paths/)

### Exam Readiness

- [ ] Aliases and vim config memorized
- [ ] CRI-dockerd kernel configuration and setup memorized
- [ ] Can install and configure kubeadm cluster from memory
- [ ] YAML templates written from memory (at least 10)
- [ ] killer.sh session 1 completed
- [ ] killer.sh session 2 completed
- [ ] Mock exam completed (>66%)
- [ ] ID verified and CNCF account name matches

---

## Mock Exams — Final Preparation

There are no fixed mock exams. `./cka` → **Mock exam** generates a new one from the [question pool](questions/) each time (for CKA, CKAD or CKS):

- Weighted like the CKA 1.37 curriculum: Troubleshooting 30%, Cluster Architecture 25%, Services & Networking 20%, Workloads & Scheduling 15%, Storage 10%.
- Questions you haven't taken come first, then the ones you failed.
- Fresh exam clusters, a hard timer, a docs-only browser and `ssh` to the nodes, as on the real exam.
- Graded automatically against the cluster state, with partial credit per check. 66% passes.
- Every exam stays in the history with its checks, your values and the solutions.

Details: [LAB.md](LAB.md).

---

## YAML Templates — Write These from Memory

On the exam it is faster to write manifests from memory (or generate them with `$do`) than to copy from the docs. The templates worth drilling are in [TEMPLATES.md](TEMPLATES.md): Pod, Deployment, Services, NetworkPolicy, PV/PVC, StorageClass, Ingress, Gateway API, RBAC, DaemonSet, StatefulSet, Jobs, ConfigMaps/Secrets, SecurityContext, quotas and more.

---

## CKA FAQ — Common Questions

### Is the CKA exam hard?

Yes. The questions themselves aren't insane, but working under the two-hour limit on a laggy remote desktop is stressful, and many people don't finish their first killer.sh attempt. The passing score is 66%, which sounds low until you realize you're typing YAML from memory while a timer counts down. Practice until you're fast, not just correct.

### Is the CKA worth it in 2026?

For most platform and SRE roles, yes. Not because of the badge — because studying for it forces you to learn etcd, kubeadm, and cluster troubleshooting, which you can deploy apps for years without touching. The cert also gets you past resume filters: platform/SRE job postings commonly list it. Whether you need the cert or just the knowledge depends on your situation.

### How long should I study for the CKA?

About 4 weeks if you already deploy apps to Kubernetes at work but have never touched etcd or kubeadm — those domains take most of the time. If you're already an admin, less. If you're brand new to Kubernetes, double it: you need to learn Kubernetes itself before the exam material. Rushing it under 3 weeks only works if you're very comfortable already.

### Do I need any prerequisites for the CKA?

Officially no. Unofficially, if you can't `vim` a file, `ssh` into a server, or read YAML without your eyes glazing over, you're going to have a bad time. The exam assumes you already know:
- Linux command line — bash, vim, systemctl, journalctl. You will live in the terminal.
- Basic networking — DNS, ports, TCP. Not deep stuff, but you need to understand why pod-to-service traffic uses port 53.
- YAML — one wrong indent and nothing works. Practice until you can spot indentation errors by looking.

You don't need Docker experience specifically. containerd is the runtime now. Docker knowledge helps but isn't required.

### What if I fail the CKA?

You get one free retake with the $445 purchase. Use it. A lot of people fail the first attempt, especially on time management, and score much higher on the retake just because they know what to expect. The retake window is 12 months, so there's no rush.

### Is the CKA exam open book?

Kind of. You can open kubernetes.io/docs, kubernetes.io/blog, and github.com/kubernetes during the exam. That's it. No Stack Overflow, no personal notes, no ChatGPT. The docs are allowed but the search is slow, so know where things are (etcd backup, kubeadm upgrade, ...) before exam day.

### Can I take the CKA remotely?

Yes, it's remote-only via PSI Secure Browser. You need a quiet room, clear desk, webcam, and mic. The proctor watches you the entire time, and you have to show your entire desk and the area under it before starting. Use a wired internet connection if you can.

### Should I take CKA or CKAD first?

CKA if you manage clusters or want to. CKAD if you only deploy apps and never touch the infrastructure. CKA first gives you the whole stack, not just the deployment side. About 40% of the content overlaps (pods, services, deployments), so whichever you do second is noticeably easier.

### How is the CKA different from CKS?

CKA is about building and fixing clusters. CKS is about locking them down — Falco rules, AppArmor and seccomp profiles, admission policies, audit logging, supply chain. CKS requires an active CKA to even register. It is worth it if your job involves Kubernetes security; this repo's lab has a CKS mode with Falco, trivy, kube-bench and gVisor on the nodes.

### How many questions are on the CKA?

The Linux Foundation describes the CKA as a two-hour performance-based exam but does not publish a fixed task count. Tasks can carry different weights, so read the task values in your exam interface and manage your time accordingly.

### What Kubernetes version is on the CKA in 2026?

The Linux Foundation FAQ lists Kubernetes v1.37 as the CKA exam environment version as of October 21, 2026. The exam environment can be updated after Kubernetes releases, so check the [official CKA FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks) close to your exam date. The lab examples in this repository target v1.35 unless a file says otherwise.

### Can I use aliases and scripts during the CKA?

Yes. You can set up any aliases, bash functions, or vim config you want at the start of the exam. The exam environment gives you a fresh terminal — set it up before starting questions.

### How fast do I get my CKA results?

Results come via email within 24 hours. You'll get a score and pass/fail. If you pass, the certificate PDF is available in your CNCF portal.

### What's the pass rate for the CKA?

The CNCF doesn't publish it. If you score 60%+ on killer.sh, you are in good shape.

---

## Final Words

If something in this guide is wrong or outdated, open a PR.

Good luck.

---

## Spread the Word

If this helps you pass, star the repo and share it wherever makes sense. And if you have exam feedback (what was different from what you expected — never the actual questions), open an issue. That's how this guide stays accurate.

Every star and issue makes this repo more visible to the next person Googling "CKA exam prep."

<p align="center">
  <a href="https://github.com/theplatformlab/CKA-Certified-Kubernetes-Administrator">
    <img src="https://img.shields.io/github/stars/theplatformlab/CKA-Certified-Kubernetes-Administrator?style=for-the-badge&logo=github" alt="GitHub Stars">
  </a>
</p>

