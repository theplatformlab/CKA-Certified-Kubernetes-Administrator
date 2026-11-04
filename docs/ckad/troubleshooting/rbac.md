# RBAC Deep Dive

RBAC scenarios: combining permissions and verifying them.

---

## Scenario 1: Grant Developer Access (Create/Update, Not Delete)

**Task:** Create a developer account that can:
- create, get, list, update, patch Deployments
- Get logs from Pods
- BUT NOT delete

**Solution:**
```bash
# 1. Create SA
kubectl create serviceaccount dev-user -n default

# 2. Create role with specific verbs
kubectl create role dev-role \
  --verb=create,get,list,update,patch \
  --resource=deployments \
  -n default

# 3. Add pod logs permission (separate)
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-logs-role
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list"]
EOF

# 4. Bind both roles
kubectl create rolebinding dev-binding \
  --role=dev-role \
  --serviceaccount=default:dev-user

kubectl create rolebinding logs-binding \
  --role=pod-logs-role \
  --serviceaccount=default:dev-user

# 5. Verify
kubectl auth can-i create deployments --as=system:serviceaccount:default:dev-user
# yes

kubectl auth can-i delete deployments --as=system:serviceaccount:default:dev-user
# no
```

---

## Scenario 2: Cross-Namespace RBAC (ClusterRole)

**Task:** ServiceAccount in 'prod' needs to read ConfigMaps in ALL namespaces.

**Solution:**
```bash
# 1. Create SA in prod namespace
kubectl create serviceaccount config-reader -n prod

# 2. Create ClusterRole (not Role)
kubectl create clusterrole config-reader-global \
  --verb=get,list \
  --resource=configmaps

# 3. Bind with ClusterRoleBinding
kubectl create clusterrolebinding config-reader-binding \
  --clusterrole=config-reader-global \
  --serviceaccount=prod:config-reader

# 4. Verify (can access any namespace)
kubectl auth can-i get configmaps --as=system:serviceaccount:prod:config-reader -n default
# yes

kubectl auth can-i get configmaps --as=system:serviceaccount:prod:config-reader -n prod
# yes

kubectl auth can-i get configmaps --as=system:serviceaccount:prod:config-reader -n monitoring
# yes
```

---

## Scenario 3: Audit — Find Over-Permissioned Accounts

**Scenario:** Given several ServiceAccounts, identify which has too many permissions.

**Debug:**
```bash
# List all SAs
kubectl get sa

# Check each SA's bindings
kubectl get rolebinding -o wide

# Check which roles each SA has
kubectl describe rolebinding <binding-name>

# View role details
kubectl describe role <role-name>

# Overly permissive example:
# Role with verb: ["*"] and resource: ["*"]
# This grants ALL permissions (admin equivalent)

# Fix: Create restrictive role with specific verbs/resources
```

---

## Scenario 4: Permission Denied — Debug Why

**Given:** ServiceAccount can't perform action.  
**Task:** Find out why and fix.

```bash
# 1. Verify SA exists
kubectl get sa <name>

# 2. Check bindings
kubectl get rolebinding | grep <sa-name>

# 3. Check role details
kubectl get role <role-name> -o yaml

# 4. Verify permission
kubectl auth can-i [verb] [resource] \
  --as=system:serviceaccount:<ns>:<sa-name> \
  -n <ns>

# 5. If "no", fix:
# Either create role with missing verb:
kubectl create role <name> \
  --verb=<missing-verb> \
  --resource=<resource>

# Or edit existing role:
kubectl edit role <name>
```

---

## Common RBAC Verbs

Use these for roles:

| Verb | Purpose |
|------|---------|
| `get` | Get single resource details |
| `list` | List all resources |
| `watch` | Watch for changes (streams updates) |
| `create` | Create new resource |
| `update` | Update existing resource (full replace) |
| `patch` | Partial update |
| `delete` | Delete resource |
| `deletecollection` | Delete multiple at once |
| `exec` | Execute commands in pod |
| `logs` | Access pod logs |
| `port-forward` | Port forwarding |
| `proxy` | Proxy to service/pod |

---

## RBAC Decision Tree

```
Need SA to...?

├─ Access a single resource type in one namespace?
│  └─ Use Role + RoleBinding
│
├─ Access multiple resource types in one namespace?
│  └─ Use Role with multiple rules + RoleBinding
│
├─ Access resources across ALL namespaces?
│  └─ Use ClusterRole + ClusterRoleBinding
│
├─ Grant admin to entire cluster?
│  └─ Use ClusterRole with verb: ["*"], resource: ["*"]
│
└─ Restrict further (e.g., read-only)?
   └─ Use verb: ["get", "list"] (NO create/delete)
```

---

## Pre-Exam RBAC Drill

Create 5 different RBAC setups under 5 minutes each:

1. **Reader:** get,list pods + configmaps (one namespace)
2. **Developer:** create,update,patch deployments (one namespace)
3. **Admin:** all permissions on deployments, services, pods (one namespace)
4. **Auditor:** get,list roles, rolebindings (all namespaces = ClusterRole)
5. **Operator:** create/delete cronjobs, manage pods (one namespace)

