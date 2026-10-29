# Exercise 20 — Pod Security Standards

> Related: [Security Context skeleton](../../skeletons/securitycontext.yaml) | [README — Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25) | **Updated May 2026**

Implement Pod Security Standards (PSS) at the namespace level to enforce security policies. This exercise covers enforcing restricted, baseline, and restricted security contexts on pods.

## Conventions

Understanding PSS troubleshooting trap patterns:

- **Primary Trap:** Wrong label format (`pod-security` vs `pod-security.kubernetes.io`) — silently ignored, no error
- **Secondary Trap (Gotcha):** PSS labels applied but pod already running — doesn't retroactively enforce
- **Validation Criteria:** Your answer is correct if:
  - Restricted namespace rejects non-compliant pods with error message (not Pending)
  - Baseline namespace allows configurable pods but rejects privileged containers
  - Audit/warn namespace allows the pod, kubectl prints a warning (warn) and the violation is recorded in the API server audit log (audit)
  - All label formats use full `pod-security.kubernetes.io/` prefix
- **Scoring:** Full credit for all 3 modes working + correct label syntax. Partial for partial enforcement.

## Context

Pod Security Standards replaced Pod Security Policies in Kubernetes 1.25+. They enforce security constraints at the namespace level through labels. The CKA tests your ability to:
- Apply PSS labels to namespaces
- Understand the three levels: restricted, baseline, and privileged
- Diagnose when pods violate security policies
- Use audit and warn modes for testing before enforcement

In Kubernetes 1.35, Pod Security Standards are part of the standard admission control process.

## Tasks

Work in namespaces `exercise-20`, `exercise-20-baseline` and `exercise-20-audit` (`./scripts/lab.sh setup 20` creates them, without any Pod Security labels).

1. Label `exercise-20` with Pod Security Standards at `restricted` level in `enforce` mode
2. Attempt to run a privileged pod `rogue` (`nginx:1.28`) in `exercise-20` — it should be rejected
3. Create a restricted-compliant pod `secure-pod` (image `nginx:1.28`) in `exercise-20` and get it Running
4. Label `exercise-20-baseline` with `baseline` level in `enforce` mode
5. Run a pod `baseline-pod` (`nginx:1.28`, no securityContext) in the baseline namespace — it should succeed (baseline allows root, it only blocks privileged features)
6. Run a pod `priv-pod` with `privileged: true` in the baseline namespace — it should be rejected
7. Label `exercise-20-audit` with `restricted` level in `audit` and `warn` mode only (no `enforce` label)
8. Run a privileged pod `audit-pod` (`nginx:1.28`) in the audit namespace — it should succeed, but kubectl prints a `Warning: would violate PodSecurity "restricted:latest"`
9. Understand where the violation went: `warn` returns it to the client, `audit` writes it to the API server audit log (the pod itself gets no annotation; kind has no audit log configured)

Validate with `./scripts/lab.sh check 20` (it also asks the API server, via `--dry-run=server`, which pods each namespace admits).

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Namespace labels for PSS use format: `pod-security.kubernetes.io/enforce=restricted`
- Three modes: `enforce` (deny), `audit` (allow but log), `warn` (allow but show warning)
- Pod security levels: `privileged` (no restrictions), `baseline` (minimal restrictions), `restricted` (modern hardening)
- `k label ns <namespace> pod-security.kubernetes.io/enforce=restricted` to add PSS labels
- `k run x --image=nginx:1.28 -n <ns> --dry-run=server` tells you whether a pod would be admitted, without creating it
- A "restricted" level pod must have: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]` and `seccompProfile.type: RuntimeDefault` (`readOnlyRootFilesystem` is good practice, but not required by PSS)
- nginx as non-root: run it as user `101` (the image's `nginx` user) and give it writable `emptyDir`s for `/var/cache/nginx`, `/var/run` and `/tmp`

</details>

## What tripped me up

> **PSS Label Format Trap (Most Common Mistake):** I wrote `pod-security/enforce=restricted` but it should be `pod-security.kubernetes.io/enforce=restricted` (full path with `.io`). The typo was silently ignored — no error, the label just didn't apply. The namespace stayed in default (permissive) mode. Always double-check with `k describe ns <namespace>` to verify labels actually exist. PSS mistakes often fail silently.
>
> **Retroactive Enforcement Trap:** I labeled a namespace with `enforce=restricted`, then a non-compliant pod was already running. I expected kubectl to reject it retroactively — it didn't. PSS labels only apply to NEW pods. Already-running pods keep running. You must delete and re-create to test. This is a common exam gotcha: the policy looks wrong because old pods don't get enforced.
>
> **Audit vs Enforce Mode Confusion:** In `audit` mode, pods run even if they violate policies. The difference: `audit` pods succeed and the violation is written to the API server audit log (not to the pod), `enforce` pods are rejected outright. I thought audit mode was broken because the non-compliant pod succeeded. That's correct behavior — audit is observe-only. Add `warn` next to `audit` so kubectl shows you the violation as a `Warning:` right away.
>
> **May 2026 Gotcha (PSS Versions):** In k8s 1.35, PSS levels are tied to specific Kubernetes API versions in the audit output. When checking audit logs, violations show a k8s version (`1.35.1`). If your audit policy and actual cluster version mismatch, some `restricted` requirements might not be enforced uniformly. Always check: `k version` to ensure cluster version matches your PSS policy expectations.
>
> **Security Context Inheritance Trap:** A pod with `securityContext.runAsNonRoot: true` at pod level can still run a container with `runAsRoot` if the container's securityContext is `runAsUser: 0`. Pod-level settings don't automatically cascade to all containers. For `restricted` enforcement, you need both pod AND container-level security contexts correct.
>
> **Namespace Deletion Cascades:** When you `k delete ns <namespace-with-pss>`, the pods in it are deleted first, then labels are removed. If you need to test label changes, it's cleaner to re-label an existing namespace rather than delete/re-create (faster for exam practice).
>
> **Three Modes Interaction:** If a namespace has all three labels (`enforce`, `audit`, `warn`), they apply in order: deny if `enforce` rejects it, then audit if allowed, then warn. Don't mix all three unless testing — audit+enforce in one namespace creates confusing logs.

## Verify

```bash
./scripts/lab.sh check 20
```

Manual checks:

```bash
# Labels use the full pod-security.kubernetes.io/ prefix
k get ns exercise-20 exercise-20-baseline exercise-20-audit --show-labels

# Restricted namespace: privileged pod rejected, compliant pod running
k run rogue --image=nginx:1.28 --privileged -n exercise-20 --dry-run=server   # Forbidden
k get pod secure-pod -n exercise-20

# Baseline namespace: plain pod runs, privileged pod rejected
k get pod baseline-pod -n exercise-20-baseline
k run priv-pod --image=nginx:1.28 --privileged -n exercise-20-baseline --dry-run=server   # Forbidden

# Audit/warn namespace: privileged pod runs, kubectl warns
k get pod audit-pod -n exercise-20-audit
```

## Cleanup

```bash
./scripts/lab.sh cleanup 20
```

<details>
<summary>Solution</summary>

```bash
# Label namespaces with PSS
k label ns exercise-20 pod-security.kubernetes.io/enforce=restricted
k label ns exercise-20-baseline pod-security.kubernetes.io/enforce=baseline
k label ns exercise-20-audit \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Test restricted enforcement — this fails:
k run rogue --image=nginx:1.28 --privileged -n exercise-20
# Error: pods "rogue" is forbidden: violates PodSecurity "restricted:latest": ...

# Create compliant pod for restricted namespace
cat <<EOF | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: exercise-20
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 101        # the nginx user of the image
    runAsGroup: 101
    fsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: nginx
    image: nginx:1.28
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache/nginx
    - name: run
      mountPath: /var/run
  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
  - name: run
    emptyDir: {}
EOF
k get pod secure-pod -n exercise-20     # Running

# Test baseline
k run baseline-pod --image=nginx:1.28 -n exercise-20-baseline
k run priv-pod --image=nginx:1.28 --privileged -n exercise-20-baseline
# Error: violates PodSecurity "baseline:latest": privileged ...
k get pods -n exercise-20-baseline

# Test audit/warn mode
k run audit-pod --image=nginx:1.28 --privileged -n exercise-20-audit
# Warning: would violate PodSecurity "restricted:latest": privileged ...
# pod/audit-pod created
k get pod audit-pod -n exercise-20-audit

# Verify labels were applied correctly
k get ns exercise-20 exercise-20-baseline exercise-20-audit -o json | jq '.items[].metadata.labels'
```

</details>
