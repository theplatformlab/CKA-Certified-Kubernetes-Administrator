# RBAC for a user and a ServiceAccount

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `staging`:

1. Create a Role named `dev-reader` that allows `get`, `list` and `watch` on Pods and Deployments, and nothing else.
2. Create a ServiceAccount named `ci-bot`.
3. Create a RoleBinding named `dev-reader-binding` that grants the Role to the user `dev-user` and to the ServiceAccount `ci-bot`.

`dev-user` must not get any permissions outside namespace `staging`.

## Hints

- `kubectl create role --verb=... --resource=...` takes several verbs and resources at once.
- A RoleBinding can have several subjects: `--user` and `--serviceaccount=<ns>:<name>` in one command.
- Test with `kubectl auth can-i <verb> <resource> -n staging --as dev-user`. ServiceAccounts are `system:serviceaccount:<ns>:<name>`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n staging create role dev-reader --verb=get,list,watch --resource=pods,deployments
k -n staging create serviceaccount ci-bot
k -n staging create rolebinding dev-reader-binding --role=dev-reader \
  --user=dev-user --serviceaccount=staging:ci-bot

k auth can-i list deployments -n staging --as dev-user                      # yes
k auth can-i list pods -n default --as dev-user                             # no
k auth can-i list deployments -n staging --as system:serviceaccount:staging:ci-bot   # yes
```

`--resource=deployments` resolves to `deployments.apps`. A Role and RoleBinding only grant access inside their namespace. That is what keeps `dev-user` out of other namespaces.
