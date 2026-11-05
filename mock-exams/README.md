# Mock Exams — CKA Practice Tests

Two timed practice exams with original tasks based on common Kubernetes administration work. They are useful for finding topics to revisit, but they are not copies of the CKA exam or a prediction of your exam score.

## Quick Start

### Easiest Way: Use the Timed Exam Runner

```bash
# Start Mock Exam 01 with a 120-minute timer
bash scripts/run-mock-exam.sh 1

# Or Mock Exam 02
bash scripts/run-mock-exam.sh 2

# Or shorten to 90 minutes for a quick test
bash scripts/run-mock-exam.sh 1 90
```

The runner shows the questions and starts the timer after you press Enter. Keep it open and use a second terminal for `kubectl`. Notes can go in `/tmp/cka-exam-answers/`; the runner creates that directory for you.

## Before You Start

Use a disposable practice cluster, not a production or shared cluster. Some tasks involve node maintenance or certificate renewal and can disrupt the control plane.

The questions are not a complete lab setup: some assume that named workloads, namespaces, controllers, or storage classes already exist. Check the matching solution for prerequisites before starting. If the required setup is missing, use a dedicated lab and prepare it first rather than improvising on a cluster you care about.

The mock titles use Kubernetes 1.37 to match this repository's current target. Check the official CKA curriculum and exam information again before your exam; both can change.

### Manual Approach (If Preferred)

1. **Read the questions file ONLY** — Do not open solutions until complete
2. **Set a 2-hour timer** — This is exam length; stick to it
3. **Solve in real Kubernetes cluster** — Use your kubeadm cluster or managed k8s
4. **Verify each solution** — Use `kubectl get`, `describe`, `logs`, etc.
5. **Finish or time expires** — Mark incomplete questions and move on
6. **Score and review** — Compare against solutions file
7. **Analyze mistakes** — Identify pattern (RBAC? Storage? Networking?)

---

## Reviewing Your Work

There is no official score mapping for these mocks. The real exam uses task weighting, while these practice questions do not provide a validated scoring model. Use your results to spot gaps, not to decide from one number whether you will pass.

For each task, check whether you met every requirement, verified the resulting cluster state, and finished within the time you set. Record any missed requirement or command you had to look up, then practice that topic again before retaking the mock.

---

## How to Use

1. **Read only the question file** (MOCK-EXAM-01.md or MOCK-EXAM-02.md)
2. **Set a 2-hour timer** — Do not exceed this time
3. **Use an isolated cluster** and prepare any resources the question says already exist
4. **Solve and verify each task**; note which requirements you completed
5. **Do NOT look at solutions** until after you finish
6. **Review solutions** — Compare your answers against the solution file
7. **Choose what to practice next** based on the requirements you missed or could not verify

## Mock Exam 01

**Focus:** Troubleshooting (30%) and Cluster Architecture (25%) domains

- 15 questions covering all CKA domains
- 2-hour time limit
- Questions emphasize Pod lifecycle, RBAC, Node management, Persistent Storage, NetworkPolicy, Helm, Containers, HPA, Ingress, Kubeadm, API Server, StatefulSets, Resource Quotas, Pod Security, and Multi-container Pods
- **Difficulty:** Medium-Hard (tests core concepts + edge cases)

**Files:**
- Questions: [MOCK-EXAM-01.md](MOCK-EXAM-01.md) ← START HERE
- Solutions: [MOCK-EXAM-01-SOLUTIONS.md](MOCK-EXAM-01-SOLUTIONS.md)

## Mock Exam 02

**Focus:** Services & Networking (20%) and Workloads (15%) domains

- 15 questions covering all CKA domains with different scenarios than Exam 01
- 2-hour time limit
- Questions emphasize Service DNS, Deployment updates, Secrets, DaemonSets, API Server debugging, ConfigMap updates, PriorityClass, Service types, CronJobs, Pod Disruption Budgets, CRDs, Pod Security Standards, StorageClass, and Resource governance
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
- Take mock exam 02 and compare which requirements were easier or still caused trouble
- Review any remaining weak questions
- Practice timed exercises (pick 3-5 exercises, complete in 15 min each)

**Phase 4 — Final Check (3-5 days)**
- Retake mock exam 01 (verify improvement held)
- Revisit any task you could not complete or verify without help
- Check the current official curriculum and exam information before scheduling

### Domain-Specific Focus

Use the topic of each missed task to choose a follow-up exercise:
- **Cluster Architecture** → Redo exercises 04, 08-10, 18, 26-27, 30
- **Troubleshooting** → Redo exercises 11, 29, review all "What tripped me up" sections
- **Workloads** → Redo exercises 06, 07, 16, 21-23
- **Services & Networking** → Redo exercises 05, 19, 20, 28
- **Storage** → Redo exercises 12, 25

Useful follow-up exercises include Exercise 04 (RBAC), Exercise 12 (storage), and Exercise 28 (NetworkPolicy).

Domain weights apply to the exam domains, not to individual exercises or questions.

---

## Real Exam Comparison

| Factor | Mock Exams | Real CKA |
|--------|-----------|----------|
| Task count | 15 in each practice mock | The Linux Foundation does not publish a fixed count |
| Time | 120 min | 120 min |
| Task timing | Estimates are listed per mock task | Varies by task and its assigned weight |
| Scoring | Self-review each task against its requirements | Follow the current Linux Foundation scoring rules |
| Kubernetes access | Your cluster | Exam cluster |
| Browser | Your own | Linux Foundation browser |
| kubectl | Both available | Both available |
| Reference material | Use what you choose for practice | Check current Linux Foundation exam rules |

---

## Tips for Mock Exam Success

### Time Management (Critical)
1. Read the questions and note any tasks you want to return to
2. Use the time estimates in the question file as a guide, not a rule
3. Move on when you are stuck; come back after completing work you know how to do
4. Leave a few minutes to check the resources you changed

### Problem-Solving Approach
1. **Understand the requirement** — Reread question twice
2. **Design solution** — Sketch YAML mentally before typing
3. **Implement** — Use imperative commands where faster
4. **Verify** — kubectl get/describe/logs to confirm
5. **Move on** — Don't second-guess

### Common Mistakes
- Creating resources without checking for errors
- Misreading a resource name or namespace
- Skipping verification
- Spending too long on one task

---

## Resources During Mock Exams

Keep these open while practicing:

| Resource | When to Use | Location |
|----------|------------|----------|
| **DIAGNOSTICS.md** | Something breaks (Pod Pending, etc.) | Top-level directory |
| **cka-cheatsheet.md** | Quick reference (commands, syntax) | `cheatsheet/` |
| **DOMAINS.md** | Understand exam focus areas | Top-level directory |
| **kubernetes.io/docs** | Look up Kubernetes behavior while studying | Online |

### Recommended Flow

```
Before Exam:
1. Read exercise READMEs "What tripped me up" sections (know common gotchas)
2. Review DOMAINS.md (refresh domain weights)

During Practice:
1. Use the references you decided to allow yourself
2. Keep track of anything you had to look up

After Practice:
1. Compare your work against each task's requirements and solution
2. Pick a related exercise for any topic that needs work
3. Retake the mock later without opening the solution first
```

---

## After Each Mock Exam

### What To Do With Mistakes

For each task you missed or could not verify:
1. Find it in `MOCK-EXAM-*-SOLUTIONS.md`
2. Read the explanation (why your answer was wrong)
3. Map to related exercise: `DOMAINS.md` shows domain → `exercises/` folder
4. Redo that exercise with gotchas in mind
5. Try the task again later without the solution open

For example, if the Service in Mock Exam 01 has no endpoints, compare its selector with the Pod labels, fix the mismatch, and verify that endpoints appear. Then practice the same diagnosis again without opening the solution.

---

## Before the Real Exam

Use the mocks as one check among several, not as a pass guarantee. Before booking, review the current official curriculum, practice the exam's allowed documentation and terminal workflow, and make sure you can complete core tasks in a clean lab without relying on the solution files.

### Exam Workflow
- Use imperative commands when they are quicker, but verify the resulting object
- Inspect resources with `kubectl get`, `describe`, and `logs`
- Test connectivity when a task involves traffic
- Check current exam rules for note-taking and allowed documentation

---

## After Completing Both Mocks

After both mocks, list the tasks you could not finish, the commands you needed to look up, and the results you forgot to verify. Use that list to choose your next practice instead of treating the number completed as a prediction of your exam result.

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

These mocks are practice material, not a readiness certificate. Recheck the official CKA curriculum and exam details close to your exam date.
