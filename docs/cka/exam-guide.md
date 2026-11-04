# CKA Exam Guide

What to know before booking and on exam day: the environment, time allocation, the mistakes that cost the most points, and how killer.sh compares. For the exam facts (cost, duration, passing score) see the [CKA overview](README.md).

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

**For practice on your laptop,** you can use the setup script in [`scripts/exam-setup.sh`](../../scripts/exam-setup.sh) to speed up drilling. But practice without these shortcuts 1-2 weeks before the exam to build command muscle memory. You need to know:
- `kubectl run ...`
- `kubectl create ...`
- `--dry-run=client -o yaml` (type it out, not an alias)
- `--force --grace-period=0` (type it out, not an alias)

Memorize the commands. That beats any alias on test day.

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
- [ ] Run through the [setup for the exam terminal](exam-guide.md#important-exam-environment-vs-practice) from memory one last time
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
