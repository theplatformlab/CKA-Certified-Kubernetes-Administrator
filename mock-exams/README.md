# Mock Exams — CKA Practice Tests

Two comprehensive practice exams that simulate real CKA exam conditions. These are **timed, full-length practice tests** designed to identify your weak areas before attempting the real CKA exam.

## Quick Start

### Easiest Way: Use the Timed Exam Runner

```bash
# Start Mock Exam 01 with countdown timer (120 minutes)
bash scripts/run-mock-exam.sh 1

# Or Mock Exam 02
bash scripts/run-mock-exam.sh 2

# Or shorten to 90 minutes for a quick test
bash scripts/run-mock-exam.sh 1 90
```

The script will:
- ✅ Show all questions
- ✅ Start a countdown timer (red warning in last 5 min)
- ✅ Remind you to save answers in `/tmp/cka-exam-answers/`
- ✅ Show solutions after exam

### Manual Approach (If Preferred)

1. **Read the questions file ONLY** — Do not open solutions until complete
2. **Set a 2-hour timer** — This is exam length; stick to it
3. **Solve in real Kubernetes cluster** — Use your kubeadm cluster or managed k8s
4. **Verify each solution** — Use `kubectl get`, `describe`, `logs`, etc.
5. **Finish or time expires** — Mark incomplete questions and move on
6. **Score and review** — Compare against solutions file
7. **Analyze mistakes** — Identify pattern (RBAC? Storage? Networking?)

---

## Exam Scoring

| Score | Interpretation | Next Step |
|-------|-----------------|-----------|
| **15/15** | Perfect — ready for real exam | Take second mock, then schedule real exam |
| **12-14/15** | Passing (80%+) — likely ready | Review missed questions, schedule real exam |
| **10-11/15** | Minimum passing (67-73%) — borderline | Review all solutions, redo weak domain exercises, retake mock |
| **9/15** | Below passing — needs work | Study the solutions, redo exercises in failed domains, retake mock |
| **<9/15** | Significant gaps — not ready | Review fundamentals, redo exercises, retake mock after 1+ week |

**Real CKA exam passing score:** 66% (10/15 questions)

These mocks are slightly **harder** than real exams, so scoring 12+/15 on mocks = confident for real exam.

---

## How to Use

1. **Read ONLY the question file** (MOCK-EXAM-01.md or MOCK-EXAM-02.md)
2. **Set a 2-hour timer** — Do not exceed this time
3. **Solve each question** in your own Kubernetes cluster or practice environment
4. **Keep score** — Track how many questions you complete correctly
5. **Do NOT look at solutions** until after you finish
6. **Review solutions** — Compare your answers against the solution file
7. **Score yourself** — 10+/15 correct = passing (66%), 12+/15 = strong, 15/15 = ready for real exam

## Mock Exam 01

**Focus:** Troubleshooting (30%) and Cluster Architecture (25%) domains

- 15 questions covering all CKA domains
- 2-hour time limit
- Questions emphasize Pod lifecycle, RBAC, Node management, Persistent Storage, NetworkPolicy, Helm, Containers, HPA, Ingress, Kubeadm, API Server, StatefulSets, Resource Quotas, Pod Security, and Multi-container Pods
- **Difficulty:** Medium-Hard (tests core concepts + edge cases)

**Files:**
- Questions: [MOCK-EXAM-01.md](exams/MOCK-EXAM-01.md) ← START HERE
- Solutions: [MOCK-EXAM-01-SOLUTIONS.md](solutions/MOCK-EXAM-01-SOLUTIONS.md)

## Mock Exam 02

**Focus:** Services & Networking (20%) and Workloads (15%) domains

- 15 questions covering all CKA domains with different scenarios than Exam 01
- 2-hour time limit
- Questions emphasize Service DNS, Deployment updates, Secrets, DaemonSets, API Server debugging, ConfigMap updates, PriorityClass, Service types, CronJobs, Certificate rotation, Pod Disruption Budgets, CRDs, Pod Security Policies, StorageClass, and Resource governance
- **Difficulty:** Medium-Hard (different mix from Exam 01, tests similar depth)

**Files:**
- Questions: [MOCK-EXAM-02.md](exams/MOCK-EXAM-02.md)
- Solutions: [MOCK-EXAM-02-SOLUTIONS.md](solutions/MOCK-EXAM-02-SOLUTIONS.md)

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
- If scoring 12+/15 consistently: ready for real exam
- If scoring <12/15: do more targeted practice before scheduling

### Domain-Specific Focus

**If you scored < 60% on:**
- **Cluster Architecture** → Redo exercises 04, 08-10, 18, 26-27, 30
- **Troubleshooting** → Redo exercises 11, 29, review all "What tripped me up" sections
- **Workloads** → Redo exercises 06, 07, 16, 21-23
- **Services & Networking** → Redo exercises 05, 19, 20, 28
- **Storage** → Redo exercises 12, 25

**Critical exercises (make sure these are solid):**
- Exercise 04 (RBAC) — 25% of exam weight
- Exercise 12 (Storage) — 10% of exam weight
- Exercise 28 (NetworkPolicy) — 13% of exam weight

---

## Real Exam Comparison

| Factor | Mock Exams | Real CKA |
|--------|-----------|----------|
| Questions | 15 | 15-17 |
| Time | 120 min | 120 min |
| Pacing | ~8 min/question | ~7 min/question |
| Passing Score | 66% (10/15) | 66% (11/17) |
| Kubernetes access | Your cluster | Exam cluster |
| Browser | Your own | Linux Foundation browser |
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
4. Retake mock if score < 12/15
```

---

## After Each Mock Exam

### Scoring Interpretation

Use the scoring table above. Then:

1. **Score 15/15:** You're ready → Take killer.sh, schedule real exam
2. **Score 12-14:** You're borderline → Review failed questions + related exercises
3. **Score 10-11:** You're barely passing → Spend 1+ week on weak domains, retake mock
4. **Score <10:** Not ready → Fundamentals review, redo exercises, retake after 1+ week

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

✅ Scored 12+/15 on both mock exams (or close)
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

### If you scored 12+/15 on both:
1. **Ready for real exam** — Schedule the CKA exam
2. **Optional:** Try killer.sh (harder than real exam, good confidence booster)
3. **Real exam tips:**
   - Arrive 15 min early for setup
   - Do warm-up questions first (easier ones)
   - Use notepad for question tracking
   - Ask proctor for clarification if unsure
   - Verify each solution explicitly (prod-like rigor)

### If you scored 10-11/15 on both:
1. **Borderline passing** — Proceed with caution
2. **Recommended:** Review all solutions, understand mistakes
3. **Spend 1 week** on weak domain (e.g., RBAC if failed authZ questions)
4. **Take one more mock** (redo the easier of the two)
5. **If 11+/15 again:** Schedule real exam
6. **If <11/15:** More practice needed

### If you scored <10/15 on either mock:
1. **Not ready** — Do not schedule real exam yet
2. **Review solutions thoroughly** — Understand each mistake
3. **Redo weak exercises** — Go back to 01-31 for that domain
4. **Wait 1-2 weeks** — Let concepts soak
5. **Retake mock** (same exam is fine for practice)
6. **When consistently 12+/15:** Schedule real exam

---

## Not Real Exam Questions

These are practice scenarios inspired by real CKA exam domains and topics. They are independently written training materials designed to help you prepare. They are NOT actual CKA exam questions. The Linux Foundation does not share real exam questions publicly. For more information, see [CONTRIBUTING.md](../CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md).

---

## Study Resources

- 📖 **Exercise Theory:** See [DOMAINS.md](../DOMAINS.md) for domain-to-exercise mapping
- 📝 **Self-Grading:** Use [GRADING.md](../GRADING.md) to score individual exercises
- 🔧 **Reference Solutions:** Check [solutions/](../solutions/) for sample implementations
- 🎓 **Official CKA:** [Linux Foundation CKA Exam](https://linuxfoundation.org/certifications/kubernetes-administrator-cka/)

---

After completing both mock exams successfully (12+/15 each), you're ready for the real CKA exam. Good luck! 🚀
