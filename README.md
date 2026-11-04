[![Tests](https://github.com/steadforce/k8s-lf-exams-trainer/actions/workflows/test.yml/badge.svg)](https://github.com/steadforce/k8s-lf-exams-trainer/actions/workflows/test.yml)
[![Lab version](https://img.shields.io/badge/Lab%20version-v1.35-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/releases/)
[![Questions](https://img.shields.io/badge/Lab%20questions-110-blue)](questions/)
[![Certifications](https://img.shields.io/badge/Lab-CKA%20%7C%20CKAD%20%7C%20CKS-326CE5)](docs/lab.md)

# Kubernetes Certification Lab — CKA, CKAD and CKS

<p align="center">
  <img src="assets/cka.png" alt="Kubernetes certification lab for CKA, CKAD and CKS">
</p>

A hands-on lab and study guides for the Linux Foundation Kubernetes exams: [CKA](https://www.cncf.io/certification/cka/), [CKAD](https://www.cncf.io/certification/ckad/) and [CKS](https://www.cncf.io/certification/cks/).

- **The lab** (`./cka`) gives you exam-style tasks on local kind clusters: practice sessions by domain or area, and timed mock exams weighted like each curriculum, graded against the live cluster state. All three exams draw from one pool of [questions](questions/).
- **The guides** cover each exam: format, environment, syllabus, commands, time management and the mistakes that cost the most points.

The lab targets Kubernetes v1.35. The exam environments can be on a newer version; check the [official FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks) before relying on version-specific details.

**Disclaimer:** This repo does not include, share, or reproduce actual exam questions. All tasks are independently designed training scenarios.

## Quick Start

You need Docker, [kind](https://kind.sigs.k8s.io/), kubectl, tmux, jq and [Go](https://go.dev/doc/install) 1.23 or newer (the first start builds the app). Some items also need helm, openssl and python3.

```bash
./cka            # opens the lab: the app on the left, your shell on the right (tmux)
./cka --here     # same, in the current terminal instead of a new window (WSL)
```

In the menu, pick the exam under **Studying for**, then start a practice session or a mock exam. The lab creates the kind clusters it needs. To set up your own shell the way the exam terminal works (aliases, vim, completion), run `bash scripts/exam-setup.sh`.

Details: [docs/lab.md](docs/lab.md).

## Documentation

| | |
|---|---|
| [docs/lab.md](docs/lab.md) | The lab: clusters, practice sessions, mock exams, keys, command line, writing an item |
| [docs/cka/](docs/cka/) | CKA guide: exam guide, syllabus, kubectl, cheat sheet, troubleshooting, study plan |
| [docs/ckad/](docs/ckad/) | CKAD guide: study plan, exam guide, kubectl, patterns, troubleshooting |
| [docs/cks/](docs/cks/) | CKS guide: exam guide, syllabus, kubectl, templates, study plan |
| [docs/templates.md](docs/templates.md) | YAML templates for the common resources |
| [docs/README.md](docs/README.md) | CKA vs CKAD vs CKS: which one to take |

## Repo Structure

```
├── cka                  # Lab launcher
├── questions/           # The task pool: task, hints, solution, setup and validator per item
├── tools/cka/           # The lab app (Go)
├── scripts/
│   ├── init-cluster.sh  # kind clusters (profiles in config/)
│   ├── lab.sh           # Setup / check / cleanup of a single item
│   ├── exam/            # Docs-only browser proxy, ssh shim, shell rc
│   ├── lib/             # Shared helpers for the validators
│   └── exam-setup.sh    # Aliases, vim config, bash completion
├── docs/                # Lab documentation and the CKA, CKAD and CKS guides
└── .github/             # CI (app tests, script syntax), issue and PR templates
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Never submit real exam questions.
