# Install an operator chart with CRDs

**Context:** `kubectl config use-context {{CONTEXT}}`

The storage team wants to manage volume snapshots with a small operator. Its Helm chart is located at `{{WORKDIR}}/charts/snapshot-operator`.

1. Install the chart as release `{{RELEASE}}` in the new namespace `snapshot-system`. The operator's CustomResourceDefinitions must be installed by this release. Do not modify the chart files.
2. The file `{{WORKDIR}}/nightly-snapshots.yaml` describes a `SnapshotPolicy` for namespace `warehouse-db`. Edit the file so that the policy keeps `{{RETAIN}}` snapshots per volume (use the field the CRD defines for this), then create the resource from the file.

## Hints

- `helm show values <chart-dir>` lists the values; one of them decides whether the CRDs are part of the release.
- `helm install <release> <chart-dir> -n <ns> --create-namespace --set a.b=c`. Installed without the CRDs? `helm upgrade <release> <chart-dir> -n <ns> --reuse-values --set ...` adds them.
- `k explain snapshotpolicy.spec` works once the CRD exists and shows the field for the number of snapshots to keep.

## Solution

```bash
k config use-context {{CONTEXT}}
helm show values {{WORKDIR}}/charts/snapshot-operator     # crds.enabled: false
helm install {{RELEASE}} {{WORKDIR}}/charts/snapshot-operator \
  -n snapshot-system --create-namespace \
  --set crds.enabled=true

helm -n snapshot-system list
k get crd snapshotpolicies.backup.cka-lab.io
k explain snapshotpolicy.spec                              # retainCount <integer>
```

Add the field to `{{WORKDIR}}/nightly-snapshots.yaml`:

```yaml
spec:
  schedule: "30 1 * * *"
  retainCount: {{RETAIN}}
  volumeSelector:
    matchLabels:
      app: warehouse-db
```

```bash
k apply -f {{WORKDIR}}/nightly-snapshots.yaml
k -n warehouse-db get snapshotpolicies             # RETAIN column shows {{RETAIN}}
```

Without `crds.enabled=true` the chart installs only the controller, and `k apply` of the policy fails with `no matches for kind "SnapshotPolicy"`. Charts like cert-manager gate their CRDs behind a value like this; CRDs in a chart's `crds/` directory are always installed (unless `--skip-crds`), but Helm never upgrades or deletes them. Applying the CRD by hand (for example from `helm template`) is not the same: the CRD would not belong to the release. The chart marks its CRD with `helm.sh/resource-policy: keep`, so `helm uninstall` leaves it, and with it all SnapshotPolicies, in place.
