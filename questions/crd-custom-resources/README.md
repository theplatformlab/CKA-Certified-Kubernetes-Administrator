# Custom resources

**Context:** `kubectl config use-context {{CONTEXT}}`

The CRD `databases.example.com` (kind `Database`) is installed.

1. In namespace `team-data`, create a `Database` named `orders-db` with `engine: postgres`, `version: "17"` and `storageGB: 20`. Use `kubectl explain` to find the schema.
2. Delete the `Database` named `legacy-db` in namespace `team-data`.
3. Write the names of all CRDs in the API group `example.com` into `{{WORKDIR}}/crds.txt`, one per line.

## Hints

- `kubectl get crd` and `kubectl explain <plural> --api-version=<group>/<version>` show the schema.
- Fields declared as strings must be quoted in YAML (`"17"`).
- `kubectl get crd -o name | grep '\.example\.com$'`

## Solution

```bash
k config use-context {{CONTEXT}}
k explain databases.spec --api-version=example.com/v1
k apply -f - <<'EOF'
apiVersion: example.com/v1
kind: Database
metadata:
  name: orders-db
  namespace: team-data
spec:
  engine: postgres
  version: "17"
  storageGB: 20
EOF
k -n team-data delete database legacy-db
k get crd -o name | grep '\.example\.com$' | cut -d/ -f2 > {{WORKDIR}}/crds.txt
```

Quote `version: "17"`. The schema declares it as a string, and an unquoted `17` is rejected. Use `grep '\.example\.com$'`, not `grep example.com`, which would also match a group like `notexample.com`.
