# RBAC for a user and a ServiceAccount

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `staging`:

1. Create a Role named `dev-reader` that allows `get`, `list` and `watch` on Pods and Deployments, and nothing else.
2. Create a ServiceAccount named `ci-bot`.
3. Create a RoleBinding named `dev-reader-binding` that grants the Role to the user `dev-user` and to the ServiceAccount `ci-bot`.
4. `ci-bot` also has to read the cluster's nodes. Create a ClusterRole named `staging-node-reader` that allows `get` and `list` on Nodes, and a ClusterRoleBinding named `ci-bot-node-reader` that grants it to `ci-bot` only.

`dev-user` must not get any permissions outside namespace `staging`.

## Hints

- `kubectl create role --verb=... --resource=...` takes several verbs and resources at once.
- A RoleBinding can have several subjects: `--user` and `--serviceaccount=<ns>:<name>` in one command.
- Nodes are cluster-scoped: a Role can't grant them, you need a ClusterRole and a ClusterRoleBinding.
- Test with `kubectl auth can-i <verb> <resource> -n staging --as dev-user`. ServiceAccounts are `system:serviceaccount:<ns>:<name>`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n staging create role dev-reader --verb=get,list,watch --resource=pods,deployments
k -n staging create serviceaccount ci-bot
k -n staging create rolebinding dev-reader-binding --role=dev-reader \
  --user=dev-user --serviceaccount=staging:ci-bot

k create clusterrole staging-node-reader --verb=get,list --resource=nodes
k create clusterrolebinding ci-bot-node-reader --clusterrole=staging-node-reader \
  --serviceaccount=staging:ci-bot

k auth can-i list deployments -n staging --as dev-user                      # yes
k auth can-i list pods -n default --as dev-user                             # no
k auth can-i list nodes --as dev-user                                       # no
k auth can-i list deployments -n staging --as system:serviceaccount:staging:ci-bot   # yes
k auth can-i list nodes --as system:serviceaccount:staging:ci-bot           # yes
k auth can-i delete nodes --as system:serviceaccount:staging:ci-bot         # no
```

`--resource=deployments` resolves to `deployments.apps`. A Role and RoleBinding only grant access inside their namespace. That is what keeps `dev-user` out of other namespaces. Cluster-scoped resources like Nodes need a ClusterRole bound with a ClusterRoleBinding.

## Pitfalls

- `--as=ci-bot` silently answers "no": a ServiceAccount is always `system:serviceaccount:<namespace>:<name>`.
- Core resources (pods, services, nodes) have the API group `""` in YAML, not `v1`.
