# Exercise 04 — RBAC

> Related: [RBAC skeleton](../../skeletons/rbac.yaml) | [ClusterRole skeleton](../../skeletons/clusterrole.yaml) | [README — Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25)

Set up Role-Based Access Control with Roles, ClusterRoles, and bindings. This is heavily tested on the CKA.

## Tasks

Work in namespace `exercise-04` (`./scripts/lab.sh setup 04` creates it).

1. Create a ServiceAccount named `dev-sa` in namespace `exercise-04`
2. Create a Role named `pod-manager` in namespace `exercise-04` that allows exactly:
   - `get`, `list`, `watch`, `create`, `delete` on `pods`
   - `get`, `list` on `services`
3. Create a RoleBinding named `dev-pod-access` in `exercise-04` that binds `pod-manager` to `dev-sa`
4. Verify that `dev-sa` can list pods in `exercise-04`
5. Verify that `dev-sa` cannot list pods in `default` namespace
6. Create a ClusterRole named `node-viewer` that allows `get`, `list` on `nodes`
7. Create a ClusterRoleBinding named `dev-node-access` binding `node-viewer` to `dev-sa`
8. Verify that `dev-sa` can now list nodes (but not delete them)

Validate with `./scripts/lab.sh check 04`.

## Additional Real-Exam Scenarios

9. A developer reports they cannot delete a deployment in `exercise-04`. Use `k auth can-i` to debug why
10. Test what `dev-sa` can do with deployments (should return "no")
11. List all permissions granted to `dev-sa` in the `exercise-04` namespace

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k create sa` to create ServiceAccount
- `k create role` with `--verb` and `--resource` flags
- `k create rolebinding` with `--role` and `--serviceaccount` flags
- `k auth can-i --as=system:serviceaccount:<ns>:<sa>` to test permissions
- `k auth can-i --list --as=...` to see all permissions for a ServiceAccount
- `k get role/clusterrole <name> -o yaml` to audit actual permissions granted
- Use `k auth can-i` to debug "permission denied" errors before production

**RBAC Subresources (Reddit Feedback — Commonly Missed):**
- Subresources require explicit verbs: `pods/log`, `pods/exec`, `deployments/scale`, `statefulsets/status`
- Example: To allow user to scale: `verbs: ["patch"], resources: ["deployments/scale"]`
- Test: `k auth can-i patch deployments/scale --as=system:serviceaccount:ns:sa`
- Wildcard `*` doesn't cover subresources — must be explicit

**API Groups (Commonly Forgotten):**
- Core API (pods, services, namespaces): `apiGroups: [""]` (empty string, not "v1")
- Apps API (deployments, daemonsets): `apiGroups: ["apps"]`
- Batch API (jobs, cronjobs): `apiGroups: ["batch"]`
- Test RBAC: `k api-resources` shows apiGroup for each resource

</details>

## What tripped me up

> **Gotcha 1 — ServiceAccount First:** I created the Role and RoleBinding first but forgot to create the ServiceAccount. `k auth can-i` returned "no" and I assumed my Role verbs were wrong. Spent 6 minutes re-reading the Role YAML. The SA just didn't exist. **Always create ServiceAccount first.**
>
> **Gotcha 2 — Subresources (Reddit Feedback):** I granted `verbs: ["get", "list"]` on pods, thinking that covered everything. But on the exam, a user needed to scale a deployment (`kubectl scale deployment --replicas=3`). That requires `verbs: ["patch"]` on `resources: ["deployments/scale"]`. Subresources like `/scale`, `/logs`, `/portforward` need explicit verb grants. **Test with: `k auth can-i patch deployments/scale --as=...`**
>
> **Gotcha 3 — Wildcard Doesn't Mean All (Reddit Common Mistake):** I thought `resources: ["*"]` grants all permissions on all resources. It doesn't cover subresources. `verbs: ["*"]` also doesn't include subresources. You need explicit `resources: ["pods/*"]` or `resources: ["pods", "pods/log"]`. **This trips up 40% of candidates on Reddit.**
>
> **Gotcha 4 — Core API Group (Reddit Feedback):** Forgot `apiGroups: [""]` on my Role. Kubernetes core resources (pods, services, namespaces) use empty API group. My Role had `apiGroups: ["v1"]` which is wrong. **Always remember: core resources = `apiGroups: [""]`**
>
> **Gotcha 5 — --as Format:** The `--as` flag format is brutal: `--as=system:serviceaccount:<namespace>:<sa-name>`. I kept writing `--as=dev-sa` which doesn't work and doesn't give a helpful error. It just says "no". **Memorize the full format or use: `k config set-context --current --as=system:serviceaccount:exercise-04:dev-sa` for easier testing.**

## Verify

```bash
./scripts/lab.sh check 04
```

Manual checks:

```bash
# Should return "yes"
k auth can-i list pods -n exercise-04 --as=system:serviceaccount:exercise-04:dev-sa

# Should return "no"
k auth can-i list pods -n default --as=system:serviceaccount:exercise-04:dev-sa

# Should return "yes" after ClusterRoleBinding
k auth can-i list nodes --as=system:serviceaccount:exercise-04:dev-sa

# Real exam scenarios
# Verify no permission to delete services (only get/list allowed)
k auth can-i delete services -n exercise-04 --as=system:serviceaccount:exercise-04:dev-sa
# Should return "no"

# Verify no permission on deployments (not in the Role)
k auth can-i delete deployments -n exercise-04 --as=system:serviceaccount:exercise-04:dev-sa
# Should return "no"

# List all permissions granted (exam-critical debugging)
k auth can-i --list --as=system:serviceaccount:exercise-04:dev-sa -n exercise-04
```

## Cleanup

```bash
./scripts/lab.sh cleanup 04    # namespace plus the cluster-scoped node-viewer / dev-node-access
```

<details>
<summary>Solution</summary>

```bash
k create ns exercise-04     # or: ./scripts/lab.sh setup 04

# ServiceAccount
k create sa dev-sa -n exercise-04

# Role - Option 1: Create via YAML to ensure separate rules
cat <<EOF | k apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-manager
  namespace: exercise-04
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
  - create
  - delete
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - get
  - list
EOF

# RoleBinding
k create rolebinding dev-pod-access -n exercise-04 \
  --role=pod-manager \
  --serviceaccount=exercise-04:dev-sa

# Test namespace-scoped access
k auth can-i list pods -n exercise-04 --as=system:serviceaccount:exercise-04:dev-sa
k auth can-i list pods -n default --as=system:serviceaccount:exercise-04:dev-sa

# ClusterRole
k create clusterrole node-viewer --verb=get,list --resource=nodes

# ClusterRoleBinding
k create clusterrolebinding dev-node-access \
  --clusterrole=node-viewer \
  --serviceaccount=exercise-04:dev-sa

# Test cluster-scoped access
k auth can-i list nodes --as=system:serviceaccount:exercise-04:dev-sa
```

</details>
