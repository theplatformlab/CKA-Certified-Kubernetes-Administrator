# Changelog

All notable changes to this CKA/CKAD/CKS prep repo are documented here.

Format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- CKAD and CKS next to CKA: choose the certification in `./cka`; one pool of 110 questions, each tagged with the curriculum area it trains, so an item counts for every exam that lists its area (93 CKA, 61 CKAD, 33 CKS).
- Practice sessions by area (e.g. Helm & Kustomize, NetworkPolicies, CoreDNS).
- Exams are graded in the background while they run, so submitting only re-checks what changed.
- `cks` cluster profile with Falco (modern eBPF), trivy, kube-bench, kubesec and gVisor; `docs/cks-wsl.md`.
- Items that break their cluster get a cluster of their own in a session (`own_cluster`).
- CKAD and CKS study guides in `docs/ckad/` and `docs/cks/`, imported from the theplatformlab CKAD and CKS repos (MIT) without their exercises, mock exams and skeletons.
- `scripts/lab.sh`: setup / check / cleanup for every item; validators check the end state on the live cluster.
- Cluster profiles in `init-cluster.sh` (`practice`, `ops`, `cni`, `runtime`). The ops cluster has the next-minor pkgs.k8s.io repo on every node for real kubeadm upgrades.
- `./cka` (Go app in `tools/cka`): practice sessions and generated mock exams from one item pool (`questions/`). Curriculum-weighted selection that prefers unseen and failed items, parametrized items, hints and checks on demand, pause/resume, history and statistics in `~/.local/share/cka-lab`.
- `questions/`: the former Mock Exam 01/02 questions as pool items with hints, plus new items for curriculum gaps.
- `ha` cluster profile (3 control planes) for highly-available control plane tasks.

### Changed
- Fixed mock exams replaced by generated exams; the old questions were rewritten to be precise, kind-compatible and gradable.
- The practice cluster now has 1 control plane + 2 workers.
- The README is a short entry point; the CKA guide moved to `docs/cka/` (exam guide, syllabus, kubectl, cheat sheet, troubleshooting, study plan), and LAB.md, TEMPLATES.md and the CKS WSL notes to `docs/`.

### Removed
- `exercises/`: every exercise is now a standard question in `questions/` or was removed as a duplicate.
- `skeletons/` (duplicated TEMPLATES.md), the exercise validation/lint scripts and the YAML-lint CI (replaced by `go test` + script syntax checks), GRADING.md, DOMAINS.md, EXAM_STRATEGY.md and REDDIT_FEEDBACK.md (exercise-based study planning that the lab replaces).
- `scripts/run-mock-exam.sh` and the fixed `mock-exams/`, replaced by `./cka`.
- The README's practice scenarios and 17 practice questions (the lab's graded items cover them) and its duplicate kubectl cheat sheet.
- The exam-feedback issue template and the Discussions links (internal repo).

---

## [1.1.0] — 2026-03-19

### Added
- 5 new exercises: Helm install/upgrade (#13), Kustomize overlays (#14), Gateway API (#15), HPA (#16), kubectl debug (#17)
- 5 new YAML skeletons: hpa, limitrange, serviceaccount, sidecar-init-container, validatingadmissionpolicy
- 6 new troubleshooting scenarios: Helm release stuck, Gateway API misconfigured, native sidecar not starting, kubectl debug not working, CSI volume mount failure, Kustomize apply not working
- Local YAML validation script (`scripts/validate-local.sh`)
- Mock exam self-scoring worksheet in README
- CHANGELOG.md

### Changed
- Exercises index updated to cover 17 exercises across all 5 CKA domains
- Skeletons index updated to list 23 templates
- README repo structure tree updated
- README badges expanded (Kubernetes version, exercise count)

### Fixed
- Repository URLs migrated from old GitHub org to theplatformlab

---

## [1.0.0] — 2026-03-01

### Added
- 12 hands-on exercises covering core CKA domains
- 18 YAML skeletons for exam-day quick recall
- kubectl cheat sheet
- Troubleshooting playbook (9 common scenarios)
- 17-question mock exam weighted to real CKA distribution
- Exam setup script with aliases, vim config, bash completion
- CI pipeline for YAML linting
- Community templates: issue templates, PR template, CONTRIBUTING.md
- Study progress tracker
- 30/45/60-day study plans
