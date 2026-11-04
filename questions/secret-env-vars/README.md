# Secrets as environment variables

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `apps`:

1. Create a Secret named `db-credentials` with the keys `DB_USER=dbuser`, `DB_PASSWORD=secret123` and `DB_NAME=appdb`.
2. Create a Deployment named `db-client`:
   - 1 replica, image `busybox:1.37`, command `sleep 3600`
   - all three keys of the Secret available as environment variables with the same names
   - no secret values written into the Deployment manifest

## Hints

- `kubectl create secret generic <name> --from-literal=K=V ...`
- `envFrom: - secretRef: name: ...` turns every key of the Secret into an environment variable.
- `kubectl set env deploy/<name> --from=secret/<name>` does it imperatively.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n apps create secret generic db-credentials \
  --from-literal=DB_USER=dbuser --from-literal=DB_PASSWORD=secret123 --from-literal=DB_NAME=appdb
k -n apps create deployment db-client --image=busybox:1.37 $do -- sleep 3600 > db-client.yaml
```

Add `envFrom` to the container:

```yaml
    spec:
      containers:
      - name: busybox
        image: busybox:1.37
        command: ["sleep", "3600"]
        envFrom:
        - secretRef:
            name: db-credentials
```

```bash
k apply -f db-client.yaml
k -n apps exec deploy/db-client -- printenv DB_USER DB_NAME
```

Alternatively, `k -n apps set env deploy/db-client --from=secret/db-credentials` creates three `secretKeyRef` entries. Both reference the Secret instead of copying its values. That is what "no secret values in the manifest" means.
