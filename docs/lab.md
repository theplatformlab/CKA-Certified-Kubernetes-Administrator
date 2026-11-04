# Kubernetes Lab — practice sessions and mock exams for CKA, CKAD and CKS

`./cka` is the interactive way to use this repo. It draws tasks from a single pool of exam-style [questions](../questions/). It sets up each task on a local kind cluster, checks your result against the live cluster state, and records every attempt.

```bash
./cka            # opens the lab: the app on the left, your shell on the right (tmux)
./cka --here     # same, in the current terminal instead of a new Windows Terminal window
```

The first start builds the app from `tools/cka`, which needs [Go](https://go.dev/doc/install) 1.23 or newer. You also need Docker, kind, kubectl, tmux and jq; some items additionally need helm, openssl and python3.

## Clusters

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

Some tasks need a cluster you can break or rebuild. Each profile is a separate kind cluster with its own config in [`scripts/config/`](../scripts/config/):

| Profile | Cluster | Used for |
|---|---|---|
| `practice` (default) | `cka-practice` | Almost all tasks |
| `ops` | `cka-ops` | kubeadm upgrade and join, static pods, broken control plane, etcd. Every node has the pkgs.k8s.io apt repo for the **next** minor version, so `apt-get install kubeadm=1.36.x-*` + `kubeadm upgrade apply` work like on a real kubeadm cluster. etcdctl is installed. |
| `cni` | `cka-cni` | Created without a CNI, so you install Calico yourself |
| `runtime` | `cka-runtime` | Docker Engine + cri-dockerd on a node |
| `ha` | `cka-ha` | 3 control planes + 1 worker behind a load balancer |
| `cks` | `cka-cks` | CKS tooling on the nodes: Falco, trivy, kube-bench, gVisor ([cks-wsl.md](cks-wsl.md)) |

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

`./cka` opens the lab: practice sessions with hints and on-demand checks, and mock exams generated from the pool and weighted like the curriculum. Results are tracked, and items you haven't done or failed come first; see [Two modes](#two-modes).

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

## Which certification

The menu's first line, **Studying for: ‹ CKA ›**, switches between CKA, CKAD and CKS (←/→ or Enter; the choice is remembered). Practice sessions, mock exams and statistics then follow that exam's curriculum and weights. There is one pool for all three: every item names the curriculum area it trains (`area`, optionally more in `areas`), and each exam takes the items whose areas its curriculum lists, so a NetworkPolicy task counts for CKA, CKAD and CKS without being duplicated. `exams: [cka]` keeps an admin-only task (static pods, crictl on a node, ...) out of the others.

## Two modes

| | Practice session | Mock exam |
|---|---|---|
| Selection | N items (1/3/5/10) from one domain or one of its areas (e.g. Helm & Kustomize, NetworkPolicies, CoreDNS), or from all domains spread like the curriculum, or items you pick yourself | 17 questions by default (adjustable in the exam setup, or `CKA_EXAM_QUESTIONS`), split by the CKA 1.37 curriculum: Troubleshooting 30%, Cluster Architecture 25%, Services & Networking 20%, Workloads & Scheduling 15%, Storage 10%. Long tasks are limited so the set fits the duration |
| Time | Soft: each item shows its recommended time next to your time on it | Hard countdown (120/90/60 min); grading starts automatically at 0 |
| Help | Hints one at a time (`h`), check any time (`c`), solution on demand (`s s`) | None. Only the docs-only browser (kubernetes.io, helm.sh, gateway-api.sigs.k8s.io) |
| Pause | `P` pauses; the menu offers "Continue" later, and clusters keep running | `P` freezes the timer, hides the question and locks the shell (pause screen). From there `u` resumes, `x` also shuts the exam clusters down (frees memory; "Continue" starts them again), `m` goes to the menu. `q` leaves the panel with the timer still running |
| Clusters | Persistent `cka-practice`, `cka-ops` (`cka-ops2`), `cka-cni`, `cka-runtime`, `cka-ha`, created on demand | Fresh `cka-exam`, `cka-exam-ops`, and `cka-exam-ops2/-cni/-runtime/-ha` when an item needs one (at most one of these per exam); built in parallel on their own docker network |
| End | `F F` grades all items, then cleans them up | `S S` submits; the exam clusters stay up so you can inspect them. Like on killer.sh, questions are graded in the background during the exam (one every 20 s or so), so submitting only re-checks the questions you had on screen since their last check |

**One item per topic.** Every item has a topic (pod-security, networkpolicy, priorityclass, ...). A generated session never contains two items of the same topic, so you don't get three Pod Security questions in one exam.

**Troubleshooting covers every area.** Troubleshooting items have an `area` that follows the curriculum bullets: cluster components (API server, scheduler, controller-manager, etcd, CoreDNS), nodes (kubelet, taints), services & networking, output streams & resource usage (logs, `kubectl top`), and application failures. With 5 troubleshooting questions (17-question exam) every area gets one; with fewer, cluster components and nodes come first.

**Which items come first.** Items you have never done come first, then items whose last attempt failed, then passed items, least recently practised first. Every exam item can also be practised; some labs (tutorial-style or multi-scenario) are practice-only.

**Parametrized items.** Some items roll their names and values per session: replica counts, ports, schedules, thresholds. The task text, hints, solution and validator all use the same values. The values are stored with the session, so the history shows exactly what you were asked.

**Namespaces.** Every namespace in the pool belongs to one item, so no two questions of a session share one.

**Exams vs. the real exam.**
- On the real exam every task has its own cluster. Here, tasks share `cka-exam` (namespaced work) and `cka-exam-ops` (control-plane work). An item whose setup breaks the cluster (API server down, broken scheduler or kubelet, etcd restore, upgrade) gets a cluster of its own, `cka-exam-ops2`, so it never blocks the other tasks. Other items that touch the same component are never drawn together.
- At most one item per exam needs a special cluster (CNI, container runtime, HA), so startup stays at a few minutes.

## Keys

Session panel:

| Key | Action |
|---|---|
| `n` / `p` (→ / ←) | next / previous item |
| `↑` `↓` `PgUp` `PgDn` | scroll |
| `h` | next hint (practice) |
| `c` | run the check for this item (practice) |
| `s s` | show the solution (practice; recorded as "solution viewed") |
| `f` | flag the item |
| `o` | overview of all items |
| `P` | pause: practice → menu; exam → pause screen (timer frozen, shell locked) |
| `Ctrl+F` | find in the question |
| `?` | all keys, including the exam desktop's (also `exam-help` in the shell) |
| `F F` / `S S` | finish the practice session / submit the exam |
| `q` | back to the menu |

The terminal behaves like the exam desktop ([LF tips](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad)): Ctrl+Shift+C / Ctrl+Shift+V copy and paste, selecting text with the mouse copies it, Ctrl+W does nothing and Ctrl+Alt+W deletes a word, the Insert key is disabled. In the shell pane, `k` and kubectl completion are set up. `ssh <node>` opens a root shell on a kind node, the way you reach nodes on the real exam. Answer files go to `~/cka-lab/qNN/`, as each task tells you. `Ctrl-b ←/→` switches panes and `Ctrl-b c` opens another shell.

The menu also has:
- **History:** every session with its score. Open one to see each item's checks, the task with your values, and the solution. Paused sessions can be resumed from there.
- **Statistics:** new, failed and passed items per domain, plus your last exam scores.
- **Clusters:** create, start, stop, recreate or delete the lab and exam clusters. A stopped cluster keeps its state and uses no memory.

History is stored in `~/.local/share/cka-lab/sessions/` (one JSON file per session).

## Command line

```bash
./cka list                       # the pool: id, area, cluster, time, weight, modes, your status, exams
./cka gen exam 120 17            # preview a generated exam: minutes, questions (creates nothing)
./cka gen practice networking 5  # preview a practice selection
./cka render <id>                # print an item's task and hints as the app shows them

./scripts/lab.sh setup <id>      # run a single item by hand
./scripts/lab.sh check <id>
./scripts/lab.sh cleanup <id>
./scripts/lab.sh params <id>     # the item's parameter values (CKA_SEED=<n> for other ones)
```

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

## Writing an item

An item is a directory `questions/<id>/` with three files:

**`item.yaml`**
```yaml
title: Roll back a broken rollout
topic: rollouts                # a generated session never has two items of one topic
area: rollouts                 # the curriculum area it trains (Exams in tools/cka/bank.go); it decides the domain in every exam
areas: [probes]                # optional: further areas, e.g. one of another exam's curriculum
exams: [cka]                   # optional: only these exams (default: every exam whose curriculum lists one of its areas)
difficulty: 1                  # 1-3
minutes: 7                     # recommended time when practising
exam_minutes: 4                # realistic time at exam pace (the exam generator fits these into the duration)
weight: 7                      # exam points
modes: [practice, exam]        # or [practice] for tutorial-style labs
namespaces: [payments]         # every namespace it uses; must be unique in the pool ({{PARAM}} allowed)
conflicts: [apiserver-manifest] # shared cluster-wide things it changes or breaks; items on one cluster sharing a tag are never drawn together
needs: [cluster-dns]           # things it relies on; never drawn with an item on the same cluster whose conflicts break them
own_cluster: true              # only if its setup breaks the cluster (API server, etcd, scheduler, a kubelet, ...): it gets a cluster of its own (cka-exam-ops2) when other items use its profile
```

**`README.md`**: `# Title`, then the task, `## Hints` (a bullet list, gentlest hint first) and `## Solution`. The app fills these placeholders:
- `{{CONTEXT}}`, `{{CLUSTER}}`
- `{{NODE_CP}}`, `{{NODE_CP2}}`, `{{NODE_CP3}}`, `{{NODE_W1}}`, `{{NODE_W2}}`
- `{{WORKDIR}}`
- every key the item's `lab_params` prints

An optional `## Pitfalls` section after the solution is shown together with it.

**`lab.sh`**:
- `LAB_CLUSTER`: `practice` | `ops` | `cni` | `runtime` | `ha` | `cks` (CKS tooling on the nodes: Falco, trivy, kube-bench, gVisor; see [cks-wsl.md](cks-wsl.md))
- `lab_params` (optional): prints `KEY=VALUE` lines using `pick`, `rand_int` and `rand_suffix` from [`scripts/lib/params.sh`](../scripts/lib/params.sh)
- `lab_setup`: idempotent; creates the starting state or breaks things
- `lab_check`: starts with a `check_gate` so an untouched item scores 0, then uses the helpers from [`scripts/lib/check.sh`](../scripts/lib/check.sh). Exams run it in the background every few minutes, so it must not change what the candidate works on (throwaway `probe` pods are fine) and should be quick
- `lab_cleanup` (optional): the item's namespaces are deleted automatically; this function undoes everything else

Test every item:
1. Run setup; the check must score 0.
2. Apply your solution; the check must pass completely.
3. Run cleanup, then setup again.
4. For parametrized items, repeat with a second `CKA_SEED`.

`go test ./...` in `tools/cka` checks that the whole pool parses: every item has a task, hints and a solution.
