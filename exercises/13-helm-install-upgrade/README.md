# Exercise 13 — Helm Install, Upgrade, and Rollback

> **Medium** | ~15 min | Domain: Cluster Architecture (25%)
>
> Related: [README — Cluster Architecture](../../README.md#domain-4--cluster-architecture-installation--configuration-25)

Install a chart, override values, upgrade to a new version, and roll back when something breaks. Helm is now a standard operational skill on the CKA.

## Tasks

Work in namespace `exercise-13`. `./scripts/lab.sh setup 13` makes sure it does **not** exist yet (and removes an old `web` release) — let Helm create it.

Chart: `podinfo/podinfo` from the repository `https://stefanprodan.github.io/podinfo` (a small, well-maintained demo app; the Deployment is named `<release>-podinfo`).

1. Add the chart repository under the name `podinfo` and update the repo cache
2. Install the chart in namespace `exercise-13`:
   - Release name: `web`
   - Chart version `6.16.0`
   - Set `replicaCount=2`
3. Verify the release is deployed and 2 pods are running
4. Upgrade the release to chart version `6.17.0` with `replicaCount=3`
5. Check the release history and confirm there are 2 revisions
6. Roll back to revision 1
7. Verify the release is back on chart `podinfo-6.16.0` with 2 replicas (history now shows 3 revisions, the last one "Rollback to 1")

Validate with `./scripts/lab.sh check 13`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `helm repo add podinfo https://stefanprodan.github.io/podinfo`
- `helm search repo podinfo --versions` lists the available chart versions
- `helm install <name> <chart> --version <v> -n <ns> --create-namespace --set key=value`
- `helm upgrade <name> <chart> --version <v> -n <ns> --set key=value`
- `helm rollback <name> <revision> -n <ns>`
- `helm history <name> -n <ns>`

</details>

## What tripped me up

> `helm install` failed with "namespace exercise-13 not found" because I forgot `--create-namespace`. Unlike `kubectl`, Helm doesn't create the namespace for you by default. I wasted 2 minutes creating the namespace manually, then realized `--create-namespace` does it in one shot. Use it every time.
>
> When rolling back, I ran `helm rollback web` without the revision number. It defaults to the previous revision, which worked in this case. But on the exam, if there are 4+ revisions and you need a specific one, you have to check `helm history` first and specify the revision number explicitly. I got lucky in practice but almost got burned on a more complex scenario.

## Verify

```bash
./scripts/lab.sh check 13
```

Manual checks:

```bash
# Release deployed, chart version
helm list -n exercise-13

# Pods running
k get pods -n exercise-13

# History: 1 install, 2 upgrade, 3 "Rollback to 1"
helm history web -n exercise-13

# After rollback
k get deploy web-podinfo -n exercise-13 -o jsonpath='{.spec.replicas}'
# Should output 2
```

## Cleanup

```bash
./scripts/lab.sh cleanup 13
```

<details>
<summary>Solution</summary>

```bash
# Add repo
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update

# Install
helm install web podinfo/podinfo --version 6.16.0 -n exercise-13 --create-namespace --set replicaCount=2

# Verify
helm list -n exercise-13
k get pods -n exercise-13

# Upgrade
helm upgrade web podinfo/podinfo --version 6.17.0 -n exercise-13 --set replicaCount=3

# Check history
helm history web -n exercise-13

# Rollback
helm rollback web 1 -n exercise-13

# Verify rollback
k get deploy web-podinfo -n exercise-13 -o jsonpath='{.spec.replicas}'
helm history web -n exercise-13
```

</details>
