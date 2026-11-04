# CKAD Guide

Study guide for the [Certified Kubernetes Application Developer](https://www.cncf.io/certification/ckad/). Practise the tasks in the lab (`./cka`, Studying for: CKAD; see [docs/lab.md](../lab.md)).

The guide was imported from [theplatformlab/CKAD-Certified-Kubernetes-Application-Developer](https://github.com/theplatformlab/CKAD-Certified-Kubernetes-Application-Developer) (MIT) and written for Kubernetes v1.35. Check version-specific details against the [current curriculum](https://github.com/cncf/curriculum).

| | |
|---|---|
| [study-plan.md](study-plan.md) | Study plans for 1 week, 2 weeks and 3-4 weeks |
| [exam-guide.md](exam-guide.md) | Time budget, when to skip, checklists per question type, exam-day tips |
| [kubectl.md](kubectl.md) | Commands by task, one-liners, muscle-memory drills |
| [patterns/](#patterns) | The six most common task patterns |
| [troubleshooting/](#troubleshooting) | Common mistakes, namespaces, containers, networking, RBAC |
| [../templates.md](../templates.md) | YAML templates |

## Exam Details

| | |
|---|---|
| **Duration** | 2 hours |
| **Questions** | 15-20 hands-on tasks |
| **Passing Score** | 66% |
| **Kubernetes Version** | Check the [official FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks); it listed v1.37 for the exam environments on October 21, 2026 |
| **Format** | Terminal-based, no multiple choice |

## Domain Weights

| Domain | Weight |
|---|---|
| Application Environment, Configuration and Security | 25% |
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Services and Networking | 20% |
| Application Observability and Maintenance | 15% |

## Patterns

| Problem | Pattern |
|---|---|
| RBAC permission denied | [patterns/rbac-debug.md](patterns/rbac-debug.md) |
| Pod won't start (CrashLoopBackOff) | [patterns/deployment-fix.md](patterns/deployment-fix.md) |
| Service has no endpoints | [patterns/service-selector-mismatch.md](patterns/service-selector-mismatch.md) |
| Network traffic blocked | [patterns/networkpolicy-allow-deny.md](patterns/networkpolicy-allow-deny.md) |
| CronJob not running | [patterns/cronjob-create.md](patterns/cronjob-create.md) |
| Ingress returns 503/404 | [patterns/ingress-debug.md](patterns/ingress-debug.md) |

## Troubleshooting

- [troubleshooting/common-mistakes.md](troubleshooting/common-mistakes.md): the errors that cost the most time
- [troubleshooting/basics.md](troubleshooting/basics.md): namespaces, labels, contexts
- [troubleshooting/containers.md](troubleshooting/containers.md): building and using container images
- [troubleshooting/networking.md](troubleshooting/networking.md): services, NetworkPolicies, DNS
- [troubleshooting/rbac.md](troubleshooting/rbac.md): RBAC scenarios and verification
