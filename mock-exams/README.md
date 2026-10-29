# Mock Exams — CKA Practice Tests

Two comprehensive practice exams that simulate real CKA exam conditions. These are **timed, full-length practice tests** designed to identify your weak areas before attempting the real CKA exam.

## Quick Start

```bash
./scripts/mock-exam.sh start 1            # Mock Exam 01, 120 minutes
./scripts/mock-exam.sh start 2 --minutes 90
```

This mirrors the real exam environment as closely as a laptop allows:

- **Fresh clusters.** Two kind clusters are built for the exam: `cka-exam` (1 control plane + 2 workers) for namespaced tasks, and `cka-exam-ops` for control-plane work (broken components, kubelet, audit logs, certificates). Your practice clusters are not touched.
- **Prepared questions.** Every question's starting state is created up front: namespaces, existing Deployments, deliberately broken components, files under `~/cka-exam/`.
- **Exam window.** A tmux session opens in a new Windows Terminal window on WSL. Use `--here` to open it in the current terminal instead. The left pane is the question panel (`n`/`p` to navigate, `f` to flag, `o` for an overview, `s` to submit). The right pane is your shell, with `k` alias and completion preconfigured, like on the real exam. Open more shells with `Ctrl-b c`. The timer runs in the status bar.
- **Context per question.** Each question starts with the `kubectl config use-context ...` you must run first, exactly like the real exam.
- **Node access.** `ssh cka-exam-ops-control-plane` opens a root shell on that node; the exam shell maps `ssh <node>` to the kind container.
- **Docs-only browser.** A separate Firefox profile opens behind a local allowlist proxy. Only kubernetes.io (docs and blog), helm.sh and gateway-api.sigs.k8s.io load. Everything else is blocked. Restart it with `./scripts/mock-exam.sh browser`.
- **Automatic grading.** When you press `s` in the question panel, run `./scripts/mock-exam.sh grade`, or the time runs out, every question is checked against the live cluster state. You get a ✓/✗ list per question, partial credit per check, and a total against the 66% pass mark. Untouched questions score 0.

```bash
./scripts/mock-exam.sh attach                     # re-open the exam window
./scripts/mock-exam.sh grade                      # grade now (can be repeated)
./scripts/mock-exam.sh stop                       # end the exam, delete the exam clusters
./scripts/mock-exam.sh question 1 7 setup|check   # re-run one question's setup or check
```

Requirements: Docker, kind, kubectl, tmux, python3, jq, helm, openssl. Firefox is optional; any browser pointed at proxy `127.0.0.1:3129` gets the same allowlist. Startup takes about 2–3 minutes (cluster creation plus question setup).

### How the real exam differs

- Each task runs on its own pre-built cluster that you reach with `ssh`. Here, namespaced tasks share `cka-exam` and control-plane tasks share `cka-exam-ops`, so a task that breaks the API server (Mock 02, Q5) also blocks the other tasks on that cluster until you fix it.
- The real exam runs in a remote desktop (PSI) with a terminal and a restricted Firefox. Here, tmux and a separate local Firefox profile do the same job.
- No answer files are collected. Like the real exam, grading looks at what exists in the cluster, plus the few output files a question explicitly asks for.

### Manual Approach

Read `MOCK-EXAM-0N.md` and work against your own cluster. To still get grading, run each question's setup first: `./scripts/mock-exam.sh question 1 <Q> setup`. That command uses clusters `cka-exam` and `cka-exam-ops`, so create them first: `CLUSTER_NAME=cka-exam ./scripts/init-cluster.sh` and `CLUSTER_NAME=cka-exam-ops ./scripts/init-cluster.sh --profile ops`.

---

## Exam Scoring

Each question has a weight (in brackets in the question title). Each one is graded with several checks, and you get `weight × passed checks / all checks`. The exam is passed at **66%**, like the real CKA.

| Score | Interpretation | Next Step |
|-------|-----------------|-----------|
| **90%+** | Ready for the real exam | Take the second mock, then schedule the exam |
| **75-89%** | Passing with margin | Review the failed checks, schedule the exam |
| **66-74%** | Borderline pass | Review all solutions, redo the related exercises, retake |
| **50-65%** | Below passing | Study the solutions, redo the exercises of the weak domains |
| **<50%** | Significant gaps | Go back to the exercises; retake the mock after 1+ week |

The grading report is saved to `.exam-runtime/result-<timestamp>.txt`.

---

## How to Use

1. **Start the exam** with `./scripts/mock-exam.sh start <N>`. Do not open the solutions.
2. **Switch the context** at the start of every question.
3. **Verify as you go** with `kubectl get`, `describe`, `logs`, and test traffic where it makes sense.
4. **Submit** with `s` in the question panel when you're done, or let the timer run out.
5. **Review** the failed checks, then read `MOCK-EXAM-0N-SOLUTIONS.md` for those questions.
6. **Fix and re-grade.** The clusters stay up until `stop`, so you can repair a question and run `./scripts/mock-exam.sh grade` again.

## Mock Exam 01

**Focus:** Troubleshooting (30%) and Cluster Architecture (25%) domains

- 15 questions covering all CKA domains
- 2-hour time limit
- Questions emphasize Pod troubleshooting, RBAC, node drain, static PVs, NetworkPolicy, Helm, kubelet/runtime repair, API server audit logging, HPA, Ingress, a broken scheduler, StatefulSets, quotas, Pod Security and native sidecars
- **Difficulty:** Medium-Hard (tests core concepts + edge cases)

**Files:**
- Questions: [MOCK-EXAM-01.md](MOCK-EXAM-01.md) ← START HERE
- Solutions: [MOCK-EXAM-01-SOLUTIONS.md](MOCK-EXAM-01-SOLUTIONS.md)

## Mock Exam 02

**Focus:** Services & Networking (20%) and Workloads (15%) domains

- 16 questions covering all CKA domains with different scenarios than Exam 01
- 2-hour time limit
- Questions emphasize Service DNS, rollbacks, Secrets, DaemonSets, a broken API server, ConfigMap updates, PriorityClass, NodePort Services, CronJobs, certificate renewal, Pod Disruption Budgets, CRDs, Pod Security Admission, default StorageClass, resource governance and Gateway API
- **Difficulty:** Medium-Hard (different mix from Exam 01, tests similar depth)

**Files:**
- Questions: [MOCK-EXAM-02.md](MOCK-EXAM-02.md)
- Solutions: [MOCK-EXAM-02-SOLUTIONS.md](MOCK-EXAM-02-SOLUTIONS.md)

---

## Study Recommendations

### Exam Prep Timeline (Recommended)

**Phase 1 — Foundation (1-2 weeks)**
- Complete exercises 01-10 (basic concepts)
- Take mock exam 01 (diagnostic) — expect lower score
- Review mock solutions, identify gaps

**Phase 2 — Deep Dive (2-3 weeks)**
- Complete exercises 11-31 (advanced topics)
- Complete [GRADING.md](../GRADING.md) self-assessment
- Spend 1+ week on weak areas identified from mock 01

**Phase 3 — Refinement (1 week)**
- Take mock exam 02 (should see improvement)
- Review any remaining weak questions
- Practice timed exercises (pick 3-5 exercises, complete in 15 min each)

**Phase 4 — Final Check (3-5 days)**
- Retake mock exam 01 (verify improvement held)
- If scoring 75%+ consistently: ready for real exam
- If scoring below 75%: do more targeted practice before scheduling

### Domain-Specific Focus

**If you scored < 60% on:**
- **Cluster Architecture** → Redo exercises 04, 08-10, 18, 26-27, 30
- **Troubleshooting** → Redo exercises 11, 29, review all "What tripped me up" sections
- **Workloads** → Redo exercises 06, 07, 16, 21-23
- **Services & Networking** → Redo exercises 05, 19, 20, 28
- **Storage** → Redo exercises 12, 25

**Critical exercises (make sure these are solid):**
- Exercise 04 (RBAC) — part of the 25% Cluster Architecture domain
- Exercise 12 (Storage) — 10% of exam weight
- Exercise 28 (NetworkPolicy) — part of the 20% Services & Networking domain

Domain weights apply to the exam domains, not to individual exercises or questions.

---

## Real Exam Comparison

| Factor | Mock Exams | Real CKA |
|--------|-----------|----------|
| Task count | 15–16 in each practice mock | The Linux Foundation does not publish a fixed count |
| Time | 120 min | 120 min |
| Average time per task | ~8 minutes | Varies by task and its assigned weight |
| Passing Score | 66% (automatic grading, partial credit) | 66% |
| Kubernetes access | Fresh kind clusters `cka-exam` / `cka-exam-ops` | One pre-built cluster per task |
| Browser | Local Firefox, docs-only allowlist | PSI remote desktop, docs-only Firefox |
| kubectl | Both available | Both available |
| kubernetes.io/docs | Allowed (good to practice) | **Allowed during real exam** |

---

## Tips for Mock Exam Success

### Time Management (Critical)
1. **First 5 min:** Read all 15 questions, circle easy/hard ones
2. **Answer easy first** (5-7 min each) — quick confidence wins
3. **Tackle medium** (8-10 min each) — most of your points
4. **Skip hard** initially (12-15 min each) — revisit if time allows
5. **Last 5 min:** Verify top answers, don't introduce new mistakes

### Problem-Solving Approach
1. **Understand the requirement** — Reread question twice
2. **Design solution** — Sketch YAML mentally before typing
3. **Implement** — Use imperative commands where faster
4. **Verify** — kubectl get/describe/logs to confirm
5. **Move on** — Don't second-guess

### Common Mistakes to Avoid ❌
- ❌ Creating resources without checking for errors
- ❌ Forgetting to test cross-namespace connectivity
- ❌ Misreading pod/service/deployment names
- ❌ Skipping verification (assume it works)
- ❌ Editing wrong file (copy-paste from wrong exercise)
- ❌ Forgetting namespace (default vs specified)
- ❌ Spending too long on one question (5 min? move on)

---

## Resources During Mock Exams

Keep these open while practicing:

| Resource | When to Use | Location |
|----------|------------|----------|
| **DIAGNOSTICS.md** | Something breaks (Pod Pending, etc.) | Top-level directory |
| **DIAGNOSTICS.md** | Troubleshooting flowcharts by symptom | Top-level directory |
| **cka-cheatsheet.md** | Quick reference (commands, syntax) | `cheatsheet/` |
| **DOMAINS.md** | Understand exam focus areas | Top-level directory |
| **kubernetes.io/docs** | Official docs (allowed during exam) | Online |

### Recommended Flow

```
Before Exam:
1. Read exercise READMEs "What tripped me up" sections (know common gotchas)
2. Review DOMAINS.md (refresh domain weights)

During Exam:
1. First 5 min: Read questions, reference DIAGNOSTICS.md if stuck
2. While solving: DIAGNOSTICS.md if stuck
3. Reference: cka-cheatsheet.md for kubectl syntax

After Exam:
1. Score using GRADING.md scale
2. Identify weak domain in DOMAINS.md
3. Do 2-3 related exercises for remediation
4. Retake mock if score < 75%
```

---

## After Each Mock Exam

### Scoring Interpretation

Use the scoring table above. Then:

1. **Score 90%+:** You're ready → Take killer.sh, schedule real exam
2. **Score 75-89%:** You're borderline → Review failed questions + related exercises
3. **Score 66-74%:** You're barely passing → Spend 1+ week on weak domains, retake mock
4. **Score <66%:** Not ready → Fundamentals review, redo exercises, retake after 1+ week

### What To Do With Mistakes

For each wrong question:
1. Find it in `MOCK-EXAM-*-SOLUTIONS.md`
2. Read the explanation (why your answer was wrong)
3. Map to related exercise: `DOMAINS.md` shows domain → `exercises/` folder
4. Redo that exercise with gotchas in mind
5. Mark in GRADING.md as "revisited"

### Sample Fix Workflow

```
Q4: "Create NetworkPolicy to deny all ingress"
Answer: Incorrect (forgot to include default-deny egress rule)

Map to domain: Networking (Exercise 05)
Redo: exercises/05-networkpolicy/
Fix: Review "What tripped me up" section
RetestL Take mock again week later

Result: Q4 now scored correctly
```

---

## Final Exam Day Readiness

Before scheduling real CKA exam, verify:

✅ Scored 75%+ on both mock exams (or close)
✅ Can consistently diagnose using DIAGNOSTICS.md
✅ Know common gotchas from exercise READMEs
✅ Passed killer.sh (if available in your cluster)
✅ Refreshed all 7 red-flag exercises (04, 05, 11, 12, 16, 28, 29)

If all ✅ → Schedule exam. You're ready for 85%+ score.

### Success Tips ✓
- ✓ Use imperative commands when possible (faster than YAML)
- ✓ Always verify your work before moving on
- ✓ kubectl get/describe/logs are your debugging friends
- ✓ Use `k get RESOURCE -o yaml` to inspect created resources
- ✓ Test connectivity with `curl`, `wget`, `telnet` where needed
- ✓ Document nothing (you can't copy-paste on real exam)
- ✓ Take breaks between mock exams (at least 2-3 days)

---

## After Completing Both Mocks

### If you scored 75%+ on both:
1. **Ready for real exam** — Schedule the CKA exam
2. **Optional:** Try killer.sh (harder than real exam, good confidence booster)
3. **Real exam tips:**
   - Arrive 15 min early for setup
   - Do warm-up questions first (easier ones)
   - Use notepad for question tracking
   - Ask proctor for clarification if unsure
   - Verify each solution explicitly (prod-like rigor)

### If you scored 66-74% on both:
1. **Borderline passing** — Proceed with caution
2. **Recommended:** Review all solutions, understand mistakes
3. **Spend 1 week** on weak domain (e.g., RBAC if failed authZ questions)
4. **Take one more mock** (redo the easier of the two)
5. **If 70%+ again:** Schedule real exam
6. **If below 70%:** More practice needed

### If you scored <66% on either mock:
1. **Not ready** — Do not schedule real exam yet
2. **Review solutions thoroughly** — Understand each mistake
3. **Redo weak exercises** — Go back to the relevant exercise for that domain
4. **Wait 1-2 weeks** — Let concepts soak
5. **Retake mock** (same exam is fine for practice)
6. **When consistently 75%+:** Schedule real exam

---

## Not Real Exam Questions

These are practice scenarios inspired by real CKA exam domains and topics. They are independently written training materials designed to help you prepare. They are NOT actual CKA exam questions. The Linux Foundation does not share real exam questions publicly. For more information, see [CONTRIBUTING.md](../CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md).

---

## Study Resources

- 📖 **Exercise Theory:** See [DOMAINS.md](../DOMAINS.md) for domain-to-exercise mapping
- 📝 **Self-Grading:** Use [GRADING.md](../GRADING.md) to score individual exercises
- 🔧 **Reference Solutions:** See [Mock Exam 01 solutions](MOCK-EXAM-01-SOLUTIONS.md) and [Mock Exam 02 solutions](MOCK-EXAM-02-SOLUTIONS.md)
- 🎓 **Official CKA:** [Linux Foundation CKA Exam](https://linuxfoundation.org/certifications/kubernetes-administrator-cka/)

---

After completing both mock exams successfully (75%+ each), you're ready for the real CKA exam. Good luck! 🚀
