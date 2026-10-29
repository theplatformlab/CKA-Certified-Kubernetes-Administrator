# CKA Lab — practice sessions and mock exams

`./cka` is the interactive way to use this repo. It draws tasks from a single pool of items: the [exercises](exercises/) and the exam-style [questions](questions/). It sets up each task on a local kind cluster, checks your result against the live cluster state, and records every attempt.

```bash
./cka            # opens the lab: the app on the left, your shell on the right (tmux)
./cka --here     # same, in the current terminal instead of a new Windows Terminal window
```

The first start builds the app from `tools/cka`, which needs [Go](https://go.dev/doc/install) 1.23 or newer. You also need Docker, kind, kubectl, tmux and jq; some items additionally need helm, openssl and python3.

## Two modes

| | Practice session | Mock exam |
|---|---|---|
| Selection | N items (1/3/5/10), optionally from one domain, or items you pick yourself | Generated, weighted like the CKA 1.37 curriculum: Troubleshooting 30%, Cluster Architecture 25%, Services & Networking 20%, Workloads & Scheduling 15%, Storage 10% |
| Time | Soft: each item shows its recommended time next to your time on it | Hard countdown (120/90/60 min); grading starts automatically at 0 |
| Help | Hints one at a time (`h`), check any time (`c`), solution on demand (`s s`) | None. Only the docs-only browser (kubernetes.io, helm.sh, gateway-api.sigs.k8s.io) |
| Pause | `P` pauses, and the menu offers "Continue" later. Clusters keep their state | No pause; `q` leaves the panel while the timer keeps running |
| Clusters | Persistent `cka-practice`, `cka-ops`, `cka-cni`, `cka-runtime`, `cka-ha`, created on demand | Fresh `cka-exam`, `cka-exam-ops`, and `cka-exam-cni/-runtime/-ha` when an item needs one; built in parallel on their own docker network |
| End | `F F` grades all items, then cleans them up | `S S` submits; the exam clusters stay up so you can inspect them |

**Which items come first.** Items you have never done come first, then items whose last attempt failed, then passed items, least recently practised first. Every exam item can also be practised; some labs (tutorial-style or multi-scenario) are practice-only.

**Parametrized items.** Some items roll their names and values per session: replica counts, ports, schedules, thresholds. The task text, hints, solution and validator all use the same values. The values are stored with the session, so the history shows exactly what you were asked.

**Exams vs. the real CKA.**
- On the real exam every task has its own cluster. Here, tasks share `cka-exam` (namespaced work) and `cka-exam-ops` (control-plane work). Items that touch the same component, such as two that break the API server, are never drawn together.
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
| `P` | pause (practice) |
| `F F` / `S S` | finish the practice session / submit the exam |
| `q` | back to the menu |

In the shell pane, `k` and kubectl completion are set up. `ssh <node>` opens a root shell on a kind node, the way you reach nodes on the real exam. Answer files go to `~/cka-lab/qNN/`, as each task tells you. `Ctrl-b ←/→` switches panes and `Ctrl-b c` opens another shell.

The menu also has:
- **History:** every session with its score. Open one to see each item's checks, the task with your values, and the solution. Paused sessions can be resumed from there.
- **Statistics:** new, failed and passed items per domain, plus your last exam scores.
- **Clusters:** create, recreate or delete the lab and exam clusters.

History is stored in `~/.local/share/cka-lab/sessions/` (one JSON file per session).

## Command line

```bash
./cka list                       # the pool: id, domain, cluster, time, weight, modes, your status
./cka gen exam 120               # preview a generated exam (creates nothing)
./cka gen practice networking 5  # preview a practice selection
./cka render <id>                # print an item's task and hints as the app shows them

./scripts/lab.sh setup <id>      # run a single item by hand (exercise number or question id)
./scripts/lab.sh check <id>
./scripts/lab.sh cleanup <id>
./scripts/lab.sh params <id>     # the item's parameter values (CKA_SEED=<n> for other ones)
```

## Writing an item

An item is a directory in `questions/<id>/` (or `exercises/<NN>-<name>/`) with three files:

**`item.yaml`**
```yaml
title: Roll back a broken rollout
domain: workloads              # troubleshooting | architecture | networking | workloads | storage
difficulty: 1                  # 1-3
minutes: 7                     # realistic exam time
weight: 7                      # exam points
modes: [practice, exam]        # or [practice] for tutorial-style labs
namespaces: [payments]         # every namespace it uses; must be unique in the pool ({{PARAM}} allowed)
conflicts: [apiserver-manifest] # shared cluster-wide things it changes; items sharing a tag are never drawn together
order: late                    # only if its setup leaves the API server down
```

**`README.md`**: `# Title`, then the task, `## Hints` (a bullet list, gentlest hint first) and `## Solution`. The app fills these placeholders:
- `{{CONTEXT}}`, `{{CLUSTER}}`
- `{{NODE_CP}}`, `{{NODE_CP2}}`, `{{NODE_CP3}}`, `{{NODE_W1}}`, `{{NODE_W2}}`
- `{{WORKDIR}}`
- every key the item's `lab_params` prints

Exercise READMEs keep their richer format (Tasks, Hints, What tripped me up, Verify, Cleanup, Solution); the app picks out the parts it needs.

**`lab.sh`**:
- `LAB_CLUSTER`: `practice` | `ops` | `cni` | `runtime` | `ha`
- `lab_params` (optional): prints `KEY=VALUE` lines using `pick`, `rand_int` and `rand_suffix` from [`scripts/lib/params.sh`](scripts/lib/params.sh)
- `lab_setup`: idempotent; creates the starting state or breaks things
- `lab_check`: starts with a `check_gate` so an untouched item scores 0, then uses the helpers from [`scripts/lib/check.sh`](scripts/lib/check.sh)
- `lab_cleanup` (optional): the item's namespaces are deleted automatically; this function undoes everything else

Test every item:
1. Run setup; the check must score 0.
2. Apply your solution; the check must pass completely.
3. Run cleanup, then setup again.
4. For parametrized items, repeat with a second `CKA_SEED`.

`go test ./...` in `tools/cka` checks that the whole pool parses: every item has a task, hints and a solution.
