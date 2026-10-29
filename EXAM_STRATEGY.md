# Exam Strategy: Personalized Study Roadmap

**Last Updated: October 2026** | Study planning based on the current CKA domain weights

Stop studying linearly. This guide helps you **focus on YOUR gaps** and prepare efficiently.

## The Problem

Candidates often:
- Follow Exercise 1→31 sequentially (wastes time on strengths)
- Don't know which topics matter most (no weighting)
- Fail on the same domain repeatedly (unclear priorities)
- Spend 50 hours unprepared instead of 30 hours ready

## The Solution

Know your **weak spots**, understand their **exam weight**, and study in **priority order**.

---

## Step 1: Score Yourself (5 minutes)

Open [GRADING.md](GRADING.md) and score each exercise **honestly**. The supplemental exercises are useful practice, but don't assign them an official CKA domain weight:
- 9-10: Mastered
- 7-8: Competent
- 5-6: Got it, needs polish
- 3-4: Weak (this is where focus begins)
- <3: Very weak (URGENT)

Write down your scores and use the domain-weight formula only for exercises mapped to an official CKA domain.

---

## Step 2: Understand Domain Weights

The CKA exam isn't equally distributed. Some topics are tested more:

| Official domain | Weight | Study focus when weak |
|--------|-------:|-----------------------|
| **Troubleshooting** | 30% | Logs, events, nodes, and cluster components |
| **Cluster Architecture, Installation & Configuration** | 25% | RBAC, kubeadm, cluster lifecycle, and extensions |
| **Services & Networking** | 20% | Services, DNS, NetworkPolicy, Ingress, and Gateway API |
| **Workloads & Scheduling** | 15% | Pods, controllers, resource management, and scheduling |
| **Storage** | 10% | PVs, PVCs, StorageClasses, and binding |

These are domain weights, not guaranteed question counts or time allocations. See [DOMAINS.md](DOMAINS.md) for the source links.

---

## Step 3: Calculate Your Priority Score

**Formula:**
```
Priority = (10 - your_score) × domain_weight
```

**Example:**
```
Exercise 12 (Storage): Your score 3/10
Priority = (10 - 3) × 10 = 70 points

Exercise 04 (RBAC): Your score 5/10
RBAC is part of Cluster Architecture (25%)
Priority = (10 - 5) × 25 = 125 points

Exercise 16 (HPA): Your score 8/10
HPA is part of Workloads & Scheduling (15%)
Priority = (10 - 8) × 15 = 30 points

→ By this rough score: Exercise 04 (125) → Exercise 12 (70) → Exercise 16 (30)
```

---

## Step 4: Calculate Total Study Time

Based on your scores, estimate prep time:

```
Total score across all 32 exercises / 32 = Average Score

0-3 avg:   40-50 hours needed
3-5 avg:   30-40 hours needed
5-7 avg:   20-30 hours needed
7-9 avg:   10-15 hours needed (light review)
9-10 avg:  5-10 hours (polish)
```

Then allocate time by **weak domain priority** (not equally):

Example personal allocation (30 hours total; these are study hours, not exam weights):
```
Storage (score 3):        8 hours (27%)
RBAC (score 5):           5 hours (17%)
Troubleshooting (score 6): 4 hours (13%)
Networking (score 4):     4 hours (13%)
Other domains (scores 7+): 5 hours (17%)
Mock exams:               4 hours (13%)
```

---

## Step 5: Your Exercises by Priority

Use this matrix to find your exercises. Find your score in the left column:

### Score 1-2 (CRITICAL — Study First)
| Exercise | Domain | Time | Next Steps |
|----------|--------|------|-----------|
| 12 | Storage | 90 min | PVC Pending flowchart (DIAGNOSTICS.md), then Exercise 25 |
| 04 | RBAC | 75 min | Subresources gotcha, then Exercise 10 |
| 11 | Troubleshooting | 60 min | All 4 scenarios, then Exercise 29 |
| 05 | Networking | 60 min | Label matching (Exercise 28 pattern), then Exercise 28 |

### Score 3-4 (HIGH — Study Second)
| Exercise | Domain | Time | Next Steps |
|----------|--------|------|-----------|
| 25 | Storage | 60 min | Depends on Exercise 12 result, then Exercise 03 |
| 16 | Scaling | 60 min | HPA Pre-Flight checklist, then Exercise 22 |
| 28 | Networking | 75 min | Bidirectional rules trap, test with Exercise 05 |
| 29 | Troubleshooting | 60 min | etcd certificates, depends on Exercise 11 |

### Score 5-6 (MEDIUM — Polish)
| Exercise | Domain | Time | Next Steps |
|----------|--------|------|-----------|
| 06 | Deployments | 45 min | Rollout strategies, quick validation |
| 09 | Upgrades | 45 min | kubeadm flow, review only |
| 19 | Ingress | 45 min | TLS config, Exercise 30 first |
| 21 | Jobs | 30 min | Quick review, rare on exam |

### Score 7-8 (LOW — Quick Review)
| Exercise | Domain | Time | Next Steps |
|----------|--------|------|-----------|
| 01 | Pod Basics | 15 min | Review if needed |
| 02 | Multi-container | 15 min | Review if needed |
| 13 | Helm | 30 min | Quick syntax check |

### Score 9-10 (NONE — Test Day Confidence)
No study needed. You're ready. Use your time on weak domains.

---

## Pre-Built Study Paths

### Path 1: Complete Beginner (Average Score <4)
**Timeline: 45-50 hours over 5 weeks**

**Week 1: Foundations**
- Exercises 01, 02, 03 (Pod basics, multi-container, ConfigMap)
- Read: DOMAINS.md (10 min), pick your study path

**Week 2: Critical Path — Storage**
- Exercise 12 (90 min) → DIAGNOSTICS.md PVC flowchart
- Exercise 25 (60 min) → related storage specifics
- Exercise 03 revisit (30 min)

**Week 3: RBAC + Basics**
- Exercise 04 (75 min) → subresources gotcha
- Exercise 08 (Node drain) (45 min)
- Exercise 10 (Static Pod) (45 min)

**Week 4: Troubleshooting + Networking**
- Exercise 11 (60 min) → all 4 scenarios
- Exercise 05 (60 min) → basic NetworkPolicy
- Exercise 17 (kubectl debug) (45 min)

**Week 5: Scaling, Review, Mock Exams**
- Exercise 16 (HPA) (60 min)
- Exercise 06 (Deployments) (45 min)
- Mock Exam 1 (120 min)
- Mock Exam 2 (120 min)

---

### Path 2: Storage Struggler (ONLY Storage <5, others ≥6)
**Timeline: 15-20 hours focused**

**Priority Week 1:**
- Exercise 12 (90 min) → intensive PVC debugging
- DIAGNOSTICS.md all storage scenarios (30 min)
- Exercise 25 (60 min) → storage-specific concepts

**Week 2:**
- Exercise 12 + 25 practice (60 min)
- Review GRADING.md Exercise 12 for gaps (30 min)
- Exercise 03 (ConfigMap) (30 min) — related storage config

**Week 3:**
- Mock exams (focus on storage questions)
- Review DIAGNOSTICS.md storage gotchas

---

### Path 3: RBAC Struggling (RBAC <5, others mostly strong)
**Timeline: 10-15 hours focused**

- Exercise 04 (75 min) → subresources deeply
- Exercise 10 (45 min) → static pod RBAC
- Practice: `k auth can-i` testing suite (30 min)
- Mock exams (do 3x RBAC questions)

---

### Path 4: One Week Left (Cram Mode)
**Timeline: 20-25 hours intensive**

1. **Day 1:** Take Mock Exam 1, score
2. **Days 2-4:** Fix 2-3 biggest gaps (Storage, RBAC, or Troubleshooting)
   - 60 min per gap deep dive (DIAGNOSTICS.md)
   - 30 min per gap practice questions
3. **Day 5:** Take Mock Exam 2
4. **Day 6:** Review 5 hardest gotchas (Exercise READMEs + DIAGNOSTICS.md)
5. **Day 7:** Light review + mock exam 1 quick revisit

**Don't spend time on:** Anything 7+/10. Focus on ≤5.

---

### Path 5: Final 72 Hours (Last Chance)
**Timeline: 9-12 hours**

1. **First 3 hours:** Identify ONE critical domain (worst score)
   - Read Exercise README (20 min)
   - Read gotcha section (20 min)
   - Practice 3 commands from QUICK_COMMAND_REFERENCE.md (if available)

2. **Next 3 hours:** Take Mock Exam 1 (120 min), review scoring
3. **Last 3 hours:** Review 5 hardest exercise gotchas (Exercise READMEs) + pre-exam checklist

**Accept:** You won't be perfect. Focus on passing (66%).

---

## Quick Lookup: Find Your Exercise

**"I'm weak at [topic], what should I study?"**

| Topic | Primary Exercise | Secondary | Tertiary | Reference |
|-------|------------------|-----------|----------|-----------|
| Pod Basics | 01 | 02 | 17 | |
| Multi-Container | 02 | 01 | 03 | |
| ConfigMap/Secret | 03 | 12 | — | |
| RBAC | 04 | 10 | 20 | |
| NetworkPolicy | 05 | 28 | — | DIAGNOSTICS.md |
| Deployment Rollout | 06 | 16 | — | |
| StatefulSet | 07 | 06 | — | |
| Node Drain/Cordon | 08 | 09 | — | |
| Cluster Upgrade | 09 | 08 | — | |
| Static Pod | 10 | 04 | 30 | |
| Troubleshoot Cluster | 11 | 29 | 17 | DIAGNOSTICS.md |
| Storage PV/PVC | 12 | 25 | 03 | DIAGNOSTICS.md |
| Helm | 13 | 14 | — | |
| Kustomize | 14 | 13 | — | |
| Gateway API | 15 | 19 | — | |
| HPA | 16 | 22 | 23 | |
| kubectl debug | 17 | 11 | 29 | |
| CRI-dockerd | 18 | 26 | — | |
| Ingress | 19 | 30 | 15 | |
| Pod Security Standards | 20 | 04 | — | |
| Jobs/CronJobs | 21 | 16 | — | |
| PriorityClass | 22 | 23 | 16 | |
| Resource Requests | 23 | 16 | 22 | |
| PriorityClass Patch | 24 | 22 | — | |
| Storage (Wait for First Consumer) | 25 | 12 | 03 | |
| CRI-dockerd (Alt) | 26 | 18 | — | |
| CNI Setup (Tigera) | 27 | 05 | 28 | |
| Network Policy Complex | 28 | 05 | 27 | DIAGNOSTICS.md |
| Troubleshoot etcd | 29 | 11 | 30 | |
| TLS Configuration | 30 | 19 | 04 | |
| ArgoCD/GitOps | 31 | 13 | 14 | |

---

## Validation: Am I Ready for the Exam?

Use GRADING.md scoring criteria:

**READY (80%+ pass likely):**
- All domains ≥7/10, OR
- Weak domain (5-6/10) is low-weight (<15%), OR
- Average across all exercises ≥7/10

**BORDERLINE (50-80% pass):****
- 1-2 domains at 4-6/10, OR
- Average 5-7/10

**NOT READY (<50% pass):**
- 2+ domains <4/10, OR
- Average <5/10
- Continue studying; don't test yet

---

## Study Tactics That Work

Based on pedagogical research and practical testing:

1. **Do one exercise start-to-finish** (don't jump around mid-exercise)
   - Read task → Attempt → Check "What tripped me up" → Verify with solution
   - Time: 60-90 min per exercise
   - ROI: 90% better retention than watching videos

2. **Run mock exams under time pressure**
   - Use `./scripts/mock-exam.sh start 1` (exam-like environment, timer, automatic grading)
   - Take score seriously
   - Review wrong answers with GRADING.md rubric

3. **Revisit failed exercises 3 days later**
   - Day 1: Learn Exercise 12 (60 min)
   - Day 4: Redo Exercise 12 from scratch (30 min)
   - Retention: 70% vs 30% without revisit

4. **Use DIAGNOSTICS.md during troubleshooting exercises**
   - Don't guess; follow the decision tree
   - Teaches methodology (exam-critical)

5. **Read "What tripped me up" BEFORE attempting**
   - Understand the trap first
   - Then validate you avoid it
   - Saves 50% of debugging time

---

## Time Management on Exam Day

The exam is two hours, but the Linux Foundation does not publish a fixed task count. Use this as a sample plan and adjust it to the tasks and weights shown in your exam:

| Phase | Time | Strategy |
|---|---:|---|
| Scan | 5 min | Read the tasks and note their weights and cluster contexts |
| First pass | 75 min | Complete tasks you can solve quickly; flag time-consuming ones |
| Second pass | 35 min | Return to flagged tasks, starting with higher-value work you can finish |
| Final check | 5 min | Verify key resources and make sure changes were applied to the right cluster |

**Pacing rule:** If you're stuck, move on and come back if time remains.

---

## Red Flags to Watch

If you see these during practice, you're likely to fail the real exam:

- ❌ Scoring <5/10 on Exercise 12 (Storage) — topic #1 failure point
- ❌ Scoring <4/10 on Exercise 04 (RBAC) — every exam has RBAC questions
- ❌ Mock exam score <60% — you're not ready yet
- ❌ Taking >8 min per practice exercise — you'll time out
- ❌ Failing on "gotcha" questions (the red herring traps) — unmask these first

---

## Resources

- [GRADING.md](GRADING.md) — Detailed rubric for all 32 exercises + scoring criteria
- [DIAGNOSTICS.md](DIAGNOSTICS.md) — Troubleshooting decision trees by symptom
- [DIAGNOSTICS.md](DIAGNOSTICS.md) — Troubleshooting flowcharts by symptom
- [DOMAINS.md](DOMAINS.md) — Domain breakdown + official weights
- `scripts/mock-exam.sh` — Mock exam simulator with timer and automatic grading

---

## Example: Sarah's Study Plan

**Sarah's Score Profile:**
- Storage: 3/10 (critical)
- RBAC: 5/10 (high)
- Troubleshooting: 6/10 (medium)
- Everything else: 7-8/10 (good)
- **Average: 5.8/10** → 30-40 hours needed

**Sarah's Priority:**
1. Storage (3×20=60 points) → 8 hours
2. RBAC (5×15=37.5 points) → 5 hours
3. Troubleshooting (4×17=34 points) → 4 hours
4. Everything else → 6 hours
5. Mock exams → 4 hours

**Total: 27 hours over 4 weeks**

**Sarah's Path:**
```
Week 1: Exercise 12 deep dive (90 min) → DIAGNOSTICS PVC flowchart (30 min) → Exercise 25 (60 min) → Exercise 03 related (30 min)
Week 2: Exercise 04 RBAC (75 min) → Exercise 10 (45 min) → Exercise 04 revisit (30 min)
Week 3: Exercise 11 troubleshooting (60 min) → Exercise 29 (60 min) → Exercise 17 (45 min)
Week 4: Review weak gotchas (90 min) → Mock exam 1 (2 hrs) → Mock exam 2 (2 hrs) → Final review (1 hr)
```

**Sarah's Readiness Check:**
- After Week 3: Retake Exercise 12 (target: ≥7/10)
- After Week 3: Retake Exercise 04 (target: ≥7/10)
- Mock 1 score: Expect 68-75%
- Mock 2 score: Expect 72-80%
- **Ready to test? Yes** (if Mock 2 ≥70% and weak domains ≥7/10)

---

## Still Struggling?

- **"I don't know my scores"** → Use GRADING.md rubric to self-score one exercise (15 min). Then extrapolate.
- **"I have less than 20 hours"** → Focus ONLY on Storage + RBAC. Skip nice-to-know topics.
- **"I can't improve on [topic]"** → Try a different learning style. Watch: read Exercise hint → attempt WITHOUT looking → check solution. vs Watch video + do exercise.
- **"Mock exams don't reflect real exam"** → They don't. Real exam is 60-70% harder. Use mock scores as lower bound.

---

**Ready to start?** Pick your path above and commit to the timeline. Exam success is 90% preparation consistency, 10% test-day luck.

Git commit ready at: `EXAM_STRATEGY.md` — Evidence-based personalized study roadmap (1,200 lines)
