# RBAC Debugging Pattern

**Curriculum domain:** Application Environment, Configuration and Security (25%), together with ConfigMaps/Secrets, SecurityContexts, resource requirements, ServiceAccounts and CRDs

---

## Problem Scenario

You're asked to:
> Create a ServiceAccount 'app-sa' in namespace 'prod-space'. Grant it permission to list and get Pods but NOT delete them.

---

## Symptoms (When It's Broken)

```bash
$ kubectl get pods
NAME              READY   STATUS
app-deployment    1/1     Running
```

Then as the app-sa user:
```bash
$ kubectl get pods
error: pods is forbidden: User "system:serviceaccount:prod-space:app-sa" cannot list resource "pods"
```

Or ➜ Permissions succeed but too broad/narrow (can delete pods shouldn't).

---

## Exact 3-Step Fix

### Step 1: Create ServiceAccount
```bash
kubectl create serviceaccount app-sa -n prod-space
```

**Verify:**
```bash
kubectl get sa -n prod-space
# NAME       SECRETS   AGE
# app-sa     1         2s
```

### Step 2: Create Role (with EXACT permissions)
```bash
kubectl create role app-reader \
  --verb=get,list \
  --resource=pods \
  -n prod-space
```

**Verify role:**
```bash
kubectl get role app-reader -n prod-space -o yaml | grep -A 5 "rules:"
# rules:
# - apiGroups:
#   - ""
#   resources:
#   - pods
#   verbs:
#   - get
#   - list
```

### Step 3: Bind Role to ServiceAccount
```bash
kubectl create rolebinding app-reader-binding \
  --role=app-reader \
  --serviceaccount=prod-space:app-sa \
  -n prod-space
```

**Verify binding:**
```bash
kubectl get rolebinding app-reader-binding -n prod-space -o yaml | grep -A 3 "subjects:"
# subjects:
# - kind: ServiceAccount
#   name: app-sa
#   namespace: prod-space
```

---

## Test It Works

```bash
# Create a test pod (if not exists)
kubectl run test-pod --image=nginx -n prod-space

# Create a pod as app-sa (using SA token from secret)
kubectl get secret -n prod-space \
  $(kubectl get sa app-sa -n prod-space -o jsonpath='{.secrets[0].name}') \
  -o jsonpath='{.data.token}' | base64 -d

# OR: test with kubectl auth (simpler)
kubectl auth can-i get pods --as=system:serviceaccount:prod-space:app-sa -n prod-space
# yes

kubectl auth can-i delete pods --as=system:serviceaccount:prod-space:app-sa -n prod-space
# no
```

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| SA created but no Role | Create Role FIRST with `--verb` and `--resource` |
| Role exists but not bound to SA | RoleBinding MUST use `--serviceaccount=NAMESPACE:SA-NAME` |
| Binding in wrong namespace | RoleBinding must be in SAME namespace as Role |
| Permissions too broad | Use `--verb=get,list` NOT `--verb=*` |
| Forgot verb (like `get` only) | Apps need BOTH `get` AND `list` to work |

---

## Exam Pattern Shortcut

When you see "grant permissions to ServiceAccount":

```bash
# 1. Create SA
kubectl create sa <name> -n <ns>

# 2. Create Role with exact verbs/resources
kubectl create role <role-name> \
  --verb=<verbs> \
  --resource=<resource> \
  -n <ns>

# 3. Bind them
kubectl create rolebinding <binding-name> \
  --role=<role-name> \
  --serviceaccount=<ns>:<sa-name> \
  -n <ns>

# 4. Verify
kubectl auth can-i <verb> <resource> \
  --as=system:serviceaccount:<ns>:<sa-name> -n <ns>
```

**Time: ~2 min if muscle-memorized. 5+ min if typing from scratch.**

---

## Real Exam Variations

- ❌ Remove delete permission from existing role → Recreate Role with fewer verbs
- ❌ ServiceAccount needs access across namespaces → Use ClusterRole + ClusterRoleBinding
- ❌ "Pod exec" permission needed → Add `pods/exec` as resource
- ❌ Verify fails even after binding → Check namespace matches; check SA name spelled exactly

