# Harden the ServiceAccounts of a namespace

**Context:** `kubectl config use-context {{CONTEXT}}`

Both Deployments in namespace `crm-portal`, `crm-api` and `crm-frontend`, run as the `default` ServiceAccount, and every pod gets its token. Only `crm-api` talks to the Kubernetes API: it reads the ConfigMaps of `crm-portal`. A security review also found that the `default` ServiceAccount of `crm-portal` has far more permissions than anyone intended.

1. The `default` ServiceAccount of `crm-portal` must no longer automount its token into pods.
2. Create a ServiceAccount `crm-api` in `crm-portal`, plus a Role and RoleBinding (both named `crm-api`) that allow it to `get`, `list` and `watch` ConfigMaps in `crm-portal`, and nothing else.
3. Make Deployment `crm-api` run as ServiceAccount `crm-api`. Its pods still need their token.
4. Find and delete the binding that gives the `default` ServiceAccount of `crm-portal` its extra permissions.
5. Afterwards no running pod of `crm-frontend` may have a ServiceAccount token mounted.

## Hints

- `automountServiceAccountToken: false` can be set on a ServiceAccount (default for its pods) and on a pod spec (wins over the ServiceAccount).
- Bindings for ServiceAccounts can live anywhere, including at cluster scope: `k get clusterrolebindings -o wide | grep crm-portal`. `k auth can-i --list --as system:serviceaccount:crm-portal:default` shows what an account can do.
- The token volume is added when a pod is created. Pods that are already running keep theirs until they are replaced (`k rollout restart`).

## Solution

```bash
k config use-context {{CONTEXT}}
k -n crm-portal patch serviceaccount default -p '{"automountServiceAccountToken": false}'

k -n crm-portal create serviceaccount crm-api
k -n crm-portal create role crm-api --verb=get,list,watch --resource=configmaps
k -n crm-portal create rolebinding crm-api --role=crm-api --serviceaccount=crm-portal:crm-api
k -n crm-portal set serviceaccount deployment crm-api crm-api

k get clusterrolebindings -o wide | grep crm-portal     # crm-portal-default-admin -> cluster-admin
k delete clusterrolebinding crm-portal-default-admin

k -n crm-portal rollout restart deployment crm-frontend
k -n crm-portal rollout status deployment crm-frontend
```

```bash
# verify
k auth can-i list configmaps -n crm-portal --as system:serviceaccount:crm-portal:crm-api   # yes
k auth can-i get secrets -n crm-portal --as system:serviceaccount:crm-portal:crm-api       # no
k auth can-i list secrets -A --as system:serviceaccount:crm-portal:default                 # no
k -n crm-portal logs deploy/crm-api --tail=1                                               # configmaps: 200
k -n crm-portal exec deploy/crm-frontend -- ls /var/run/secrets/kubernetes.io/serviceaccount   # No such file or directory
```

The `crm-api` ServiceAccount keeps the default (automount on), so its pods get a token while every other pod that just uses `default` gets none. `k set serviceaccount` changes the pod template, which starts a new rollout of `crm-api`. `crm-frontend`'s template does not change, so its running pods keep the token they got at creation: only the restart gives them pods without one. Every namespace has its own `default` ServiceAccount, and a ClusterRoleBinding to it hands the permissions to every pod that doesn't name another account, which is why it should hold no permissions at all.
