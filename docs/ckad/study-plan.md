# CKAD Study Plan

Pick a timeline by the time you have. Hands-on practice runs in the lab: `./cka`, set **Studying for** to CKAD, then practice sessions by domain or area and generated mock exams (see [docs/lab.md](../lab.md)).

---

## 1 Week Crash Course

**Total hours:** 30-40  
**Daily:** 4-6 hours  
**Goal:** Pass the exam

### Day 1-2: Core Patterns
- Read: [patterns/rbac-debug.md](patterns/rbac-debug.md)
- Read: [patterns/deployment-fix.md](patterns/deployment-fix.md)
- Read: [patterns/service-selector-mismatch.md](patterns/service-selector-mismatch.md)
- Practice: a lab practice session for each pattern's area

### Day 3-4: More Patterns + Speed
- Read: [patterns/networkpolicy-allow-deny.md](patterns/networkpolicy-allow-deny.md)
- Read: [patterns/cronjob-create.md](patterns/cronjob-create.md)
- Read: [patterns/ingress-debug.md](patterns/ingress-debug.md)
- Practice: lab practice sessions across all domains; compare your time with each item's recommended time

### Day 5: Commands
- Reference: [kubectl.md](kubectl.md)
- Practice: a 10-item lab practice session across all domains

### Day 6: Mock Exam
- Take a lab mock exam (strict 2-hour timer)
- If you score below 70%, review the weak areas the result shows

### Day 7: Final Review
- Redo the items you failed (the lab puts failed items first)
- Read: [troubleshooting/common-mistakes.md](troubleshooting/common-mistakes.md)
- Read: [exam-guide.md](exam-guide.md)
- Rest

---

## 2 Weeks

**Total hours:** 50-60  
**Daily:** 4-5 hours  
**Goal:** Strong pass

### Week 1
**Mon-Tue:** Study all 6 patterns (2-3 hours each day)
- [patterns/rbac-debug.md](patterns/rbac-debug.md)
- [patterns/deployment-fix.md](patterns/deployment-fix.md)
- [patterns/service-selector-mismatch.md](patterns/service-selector-mismatch.md)
- [patterns/networkpolicy-allow-deny.md](patterns/networkpolicy-allow-deny.md)
- [patterns/cronjob-create.md](patterns/cronjob-create.md)
- [patterns/ingress-debug.md](patterns/ingress-debug.md)

**Wed-Thu:** Lab practice sessions by domain (4-5 hours each)

**Fri:** Lab mock exam + review

**Sat-Sun:** Review weak areas

### Week 2
**Mon-Wed:** Deeper practice
- [troubleshooting/rbac.md](troubleshooting/rbac.md)
- [troubleshooting/networking.md](troubleshooting/networking.md)
- Lab practice sessions for the troubleshooting-heavy areas

**Thu:** Second lab mock exam

**Fri-Sat:** Final review
- [troubleshooting/common-mistakes.md](troubleshooting/common-mistakes.md)
- [exam-guide.md](exam-guide.md)
- Weak areas

**Sun:** Rest

---

## 3-4 Weeks

**Total hours:** 80-100  
**Daily:** Comfortable pace  
**Goal:** Confident, high pass rate

### Week 1: Patterns Foundation
- Mon-Wed: Study the patterns in depth (2-3 hours/day)
- Thu-Fri: Practice each pattern's area in the lab (2-3 hours/day)
- Sat: Review + consolidate

### Week 2: All Domains
- Mon-Wed: Lab practice sessions through every CKAD domain (2-3 hours/day)
- Thu-Fri: Speed: practice sessions at exam pace (2 hours/day)
- Sat: Lab mock exam

### Week 3: Troubleshooting
- Mon-Wed: [troubleshooting/rbac.md](troubleshooting/rbac.md) + [troubleshooting/networking.md](troubleshooting/networking.md) + [troubleshooting/containers.md](troubleshooting/containers.md) (3 hours/day)
- Thu: Practice the items you failed so far
- Fri: Second lab mock exam
- Sat: Review results

### Week 4 (if needed): Final Polish
- Mon-Wed: Focus on weak areas from the mock exams (the lab's statistics show them per domain)
- Thu-Fri: Redo specific patterns
- Sat-Sun: Final review, exam strategy

---

## Score Targets

- **Mock exam <65%:** Study more before taking the real exam
- **Mock exam 65-75%:** Ready, will likely pass
- **Mock exam 75-85%:** Very good, confident pass
- **Mock exam 85%+:** Excellent

---

## Daily Schedule Template

**4-hour morning session:**
- 30 min: Read new content
- 2 hours: Lab practice
- 1 hour: Review + notes
- 30 min: [kubectl.md](kubectl.md) reference

**2-hour evening session (optional):**
- 1 hour: A short lab practice session at exam pace
- 1 hour: Review mistakes or read [exam-guide.md](exam-guide.md)
