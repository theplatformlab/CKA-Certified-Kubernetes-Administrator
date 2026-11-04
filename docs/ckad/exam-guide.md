# CKAD Exam Guide — Time Management & Mental Checklist

**Duration:** 2 hours for ~15-20 tasks  
**Passing:** 66% (tasks are weighted, partial credit is possible)  
**Difficulty:** Medium; time pressure is the main challenge, not concepts

---

## Pre-Exam Week

### Days 1-3: Pattern Memorization
- Read each pattern file in [patterns/](patterns/) once
- Practice each pattern 2-3× from memory
- Build muscle memory for commands

### Days 4-5: Timed Practice  
- Do lab practice sessions; aim to beat each item's recommended time
- Time yourself on 5-min and 10-min scenarios
- Identify which tasks you're slowest on

### Day 6: Mock Exam
- Take a full lab mock exam (`./cka`, Studying for: CKAD) without interruption
- Time yourself strictly
- Score yourself

### Day 7: Rest
- Light review of weak areas
- Get 8+ hours sleep
- Relax

---

## Exam Day — Time Budget

```
Total: 120 minutes
Average per task: 6-8 minutes (some easier, some harder)

Expected breakdown:
- Questions 1-3: Easy tasks (2-3 min each) = 9 min
- Questions 4-8: Medium tasks (5 min each) = 25 min
- Questions 9-12: Hard tasks (8-10 min each) = 35 min
- Remaining time: 51 minutes (buffer for review/hard questions) ✓

Rule of thumb: Spend max 10 min per question.
After 10 min, either move on or mark for later.
```

---

## Strategy: When to Skip (Critical)

### SKIP If:
- ❌ You're stuck for 3+ minutes with no progress
- ❌ Part of question seems impossible (you might be misreading it)
- ❌ Syntax keeps failing and you can't debug
- ❌ You're second-guessing yourself (bad sign; move on)

### DO NOT SKIP If:
- ✅ You know how to solve it but typing is slow
- ✅ You're 80% done and close to working
- ✅ It's worth double-checking (RBAC permissions)

---

## Real-Time Decision Logic (In Exam)

```
Task appears:
  ↓
Read question carefully (2x) — 1 min
  ↓
Type command / apply YAML — 4 min
  ↓
Verify with kubectl get / describe — 1 min
  ↓
Does it work? 
  ├─ YES → Mark as done, move to next
  └─ NO → Did I understand the question correctly?
       ├─ NO → Reread, start over
       └─ YES → Obvious fix?
            ├─ YES → Fix it (1 min)
            └─ NO → Mark for later, move on
  ↓
(Spend 30 min on marked tasks at end if time available)
```

---

## Command Execution Checklist

Before hitting Enter, verify:

- [ ] **Namespace correct?** Default or `ns xyz`? Recheck requirement.
- [ ] **Names spelled exactly?** Copy from requirement, not memory.
- [ ] **Flags correct?** `--dry-run=client` NOT `--dry-run` (old syntax fails)
- [ ] **YAML valid?** Indentation matters; test with DRY-RUN first
- [ ] **Selector/label format?** `key=value`, no spaces, case-sensitive
- [ ] **Service port vs targetPort?** Common mistake; recheck
- [ ] **Image exists?** `nginx:latest` works; `nginx:99.99` fails immediately

---

## Mental Checklist Per Question Type

### RBAC (ServiceAccount + Role + Rolebinding)
- [ ] SA created first
- [ ] Role has correct verbs and resources
- [ ] RoleBinding references both
- [ ] Namespace matches (all in same namespace)
- [ ] `kubectl auth can-i` passes

### Deployment/Pod Debugging
- [ ] Image exists (check docker registry)
- [ ] Ports match (container ↔ service ↔ ingress)
- [ ] Labels match service selector
- [ ] Probes not too aggressive (initialDelaySeconds 15+)
- [ ] Replicas correct

### NetworkPolicy
- [ ] podSelector specifies who is protected
- [ ] ingress/egress rules are explicit ALLOW
- [ ] Everything else is DENIED by default
- [ ] Label selectors correct

### Service/Ingress
- [ ] Service endpoints non-empty
- [ ] Service selector matches pod labels
- [ ] Ingress backend service name correct
- [ ] Ingress backend port = service port (NOT targetPort)

### CronJob
- [ ] Schedule valid UTC format
- [ ] Command/image correct
- [ ] History limits set
- [ ] restartPolicy: OnFailure (not Always)

---

## Last 10 Minutes (If You Finish Early)

1. **Go through marked tasks** (the ones you skipped)
2. **Try 2 of them** if they look solvable now
3. **Verify completed tasks** — run kubectl to confirm state;don't trust your memory
4. **Don't go back and second-guess** — you'll only break things
5. **Click Submit**

---

## Red Flags (Stop and Reread)

- ❌ Task says "across 2 namespaces" but you're only using 1
- ❌ "Ensure traffic is DENIED" but your policy allows
- ❌ "Pod must restart every 60 sec" but no restart trigger shown
- ❌ Service shows 0 endpoints (selector mismatch, not image problem)
- ❌ Ingress gives 503 (usually backend/selector issue, rarely ingress itself)

---

## Exam Day Mental State

### Morning (Before Exam)
- Review alias commands 5× (don't spend 30 min on review)
- Drink water, eat light
- Arrive 15 min early
- **Don't cram.** You either know it or you don't.

### During Exam  
- First 10 min: do 2 easy tasks to build confidence
- Don't panic if stuck (skip, come back later)
- Don't try to be perfect (66% passing)
- Read questions N times, type once

### If You Get Stuck
- "I don't know this" ≠ "This is impossible"
- Break it down: What's the smallest piece I understand?
- Use `kubectl explain <resource>` quickly
- Compare to pattern files from memory

---

## CLI Shortcuts to Memorize

```bash
# Dry-run (test before applying)
kubectl create deployment app --image=nginx --dry-run=client -o yaml

# Get quickly  
k get all -n <ns>

# Edit (faster than kubectl describe)
k edit deployment <name>

# Scale instantly
k scale deployment <name> --replicas=5

# Port forward (test service)
k port-forward svc/<name> 8080:80

# Get one value
k get deployment app -o jsonpath='{.spec.replicas}'

# Check auth quickly
k auth can-i [verb] [resource] --as=system:serviceaccount:<ns>:<sa>

# Verify endpoints
k get endpoints <svc>  # If empty = selector wrong
```

---

## Last Reminder

**Many tasks start from something broken** (a deployment, RBAC, networking).  
**You progress by recognizing patterns, not by memorizing.**

The [patterns](patterns/) cover the most common task shapes; the curriculum's [domain weights](README.md#domain-weights) decide what to study.

