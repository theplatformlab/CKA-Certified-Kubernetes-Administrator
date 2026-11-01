# Least privilege for a ServiceAccount

**Context:** `kubectl config use-context {{CONTEXT}}`

The CI job running as ServiceAccount `deploy-bot` in namespace `shipyard` was given far too many permissions. It only rolls out new versions of the Deployments in `shipyard` and follows the result. It needs exactly:

| Resource (namespace `shipyard`) | Verbs |
|---|---|
| `deployments` (API group `apps`) | `get`, `list`, `watch`, `update`, `patch` |
| `pods` | `get`, `list`, `watch` |
| `pods/log` | `get` |

1. Create a Role `deploy-bot` and a RoleBinding `deploy-bot` in `shipyard` that grant `deploy-bot` exactly these permissions, without wildcards.
2. Find every other binding that grants `deploy-bot` permissions, in any namespace or cluster-wide, and delete it. Also delete the ClusterRole that granted the cluster-wide access.
3. Save the output of `kubectl auth can-i --list` for `deploy-bot` in namespace `shipyard` to `{{WORKDIR}}/deploy-bot-permissions.txt`.

## Hints

- ServiceAccounts are impersonated as `system:serviceaccount:<namespace>:<name>`: `k auth can-i --list --as system:serviceaccount:shipyard:deploy-bot -n shipyard`. A `*.*` row with `[*]` verbs means it can do everything.
- `k get clusterrolebindings,rolebindings -A -o wide | grep deploy-bot` lists the bindings with their subjects.
- A subresource is a resource of its own in a rule: `resources: ["pods/log"]`. `k create role` takes it as `--resource=pods/log`.

## Solution

```bash
k config use-context {{CONTEXT}}
SA=system:serviceaccount:shipyard:deploy-bot
k auth can-i --list --as $SA -n shipyard | head -3          # *.*  [] [] [*]

k get clusterrolebindings,rolebindings -A -o wide | grep deploy-bot
# clusterrolebinding.../deploy-bot-all   ClusterRole/deploy-bot-all ... shipyard/deploy-bot
# shipyard-legacy  rolebinding.../legacy-ci   ClusterRole/admin ... shipyard/deploy-bot
k delete clusterrolebinding deploy-bot-all
k delete clusterrole deploy-bot-all
k -n shipyard-legacy delete rolebinding legacy-ci
```

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deploy-bot
  namespace: shipyard
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-bot
  namespace: shipyard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: deploy-bot
subjects:
- kind: ServiceAccount
  name: deploy-bot
  namespace: shipyard
```

```bash
k apply -f deploy-bot-rbac.yaml
k auth can-i --list --as $SA -n shipyard > {{WORKDIR}}/deploy-bot-permissions.txt
k auth can-i patch deployments -n shipyard --as $SA            # yes
k auth can-i delete deployments -n shipyard --as $SA           # no
k auth can-i get pods --subresource=log -n shipyard --as $SA   # yes
k auth can-i list deployments -n shipyard-legacy --as $SA      # no
```

RBAC only adds permissions: as long as one binding grants `*`, a perfect Role changes nothing, so finding all bindings is the real work. Bindings to a ServiceAccount can live in any namespace (`legacy-ci` in `shipyard-legacy` made it admin there) and at cluster scope. `k create role deploy-bot --verb=get,list,watch,update,patch --resource=deployments.apps` works too, but one `k create role` gives every resource the same verbs, so the pod rules need a second step (or YAML as above). `pods/log` is separate from `pods`: `get pods` does not include reading logs, and `create pods/exec` would allow a shell in the containers, which the job doesn't need.
