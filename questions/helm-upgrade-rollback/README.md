# Helm repository, upgrade and rollback

**Context:** `kubectl config use-context {{CONTEXT}}`

Deploy the demo app `podinfo` with Helm. The chart `podinfo` is published in the repository `https://stefanprodan.github.io/podinfo`. The namespace `helm-apps` does not exist yet.

1. Add the repository under the name `podinfo`.
2. Install chart version `6.16.0` as release `web` in namespace `helm-apps` with `replicaCount={{REPLICAS_OLD}}`.
3. Upgrade the release to chart version `6.17.0` with `replicaCount={{REPLICAS_NEW}}`.
4. The new version has to be withdrawn: roll the release back to its first revision.

Afterwards the release must run chart `podinfo-6.16.0` with {{REPLICAS_OLD}} Ready replicas, and its history must show the install, the upgrade and the rollback.

## Hints

- `helm search repo podinfo --versions` lists the chart versions once the repo is added.
- `helm install` doesn't create the namespace unless you pass `--create-namespace`.
- `helm history <release> -n <ns>` shows the revisions; `helm rollback <release> <revision> -n <ns>`.

## Solution

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update

helm install web podinfo/podinfo --version 6.16.0 -n helm-apps --create-namespace \
  --set replicaCount={{REPLICAS_OLD}}
helm upgrade web podinfo/podinfo --version 6.17.0 -n helm-apps --set replicaCount={{REPLICAS_NEW}}

helm history web -n helm-apps        # 1 install, 2 upgrade
helm rollback web 1 -n helm-apps
helm history web -n helm-apps        # 3 "Rollback to 1"
k -n helm-apps get deploy web-podinfo   # {{REPLICAS_OLD}}/{{REPLICAS_OLD}}
```

A rollback is a new revision (3) with the chart and values of revision 1; the history only moves forward.

## Pitfalls

- `helm rollback web` without a revision goes back one step. With more revisions, read `helm history` and name the target explicitly.
- `helm upgrade` without `--set` (or `--reuse-values`) resets every value you set at install time to the chart default.
