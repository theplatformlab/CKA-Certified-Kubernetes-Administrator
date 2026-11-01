# Query the API with a ServiceAccount token

**Context:** `kubectl config use-context {{CONTEXT}}`

An inventory job in namespace `keystore` will read its Secrets straight from the Kubernetes API. The ServiceAccount `inventory-sync` and its RBAC permissions already exist. Test the access from inside a pod:

1. Create a pod `api-client` in namespace `keystore` with image `curlimages/curl:8.17.0` and the command `sleep 1d`. It must run as ServiceAccount `inventory-sync`.
2. From inside the pod, use `curl` with the pod's ServiceAccount token and the cluster CA certificate (do not skip TLS verification) to list all Secrets of namespace `keystore` through the API.
3. Save the complete JSON response into `{{WORKDIR}}/secrets.json` on your host.

Do not change the ServiceAccount or its RBAC.

## Hints

- The kubelet mounts the token, `ca.crt` and `namespace` into `/var/run/secrets/kubernetes.io/serviceaccount/`. If the directory is missing in your pod, look at the ServiceAccount: `automountServiceAccountToken` can be overridden in the pod spec.
- Inside the cluster the API server is `https://kubernetes.default.svc`. Secrets of a namespace are at `/api/v1/namespaces/<ns>/secrets`.
- `curl --cacert <ca.crt> -H "Authorization: Bearer $(cat <token>)" <url>`. Run it with `k exec ... -- sh -c '...'` and redirect the output on your host.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n keystore get sa inventory-sync -o yaml                 # automountServiceAccountToken: false
k -n keystore describe rolebinding                          # Role secret-lister: list secrets

cat <<EOF2 | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: api-client
  namespace: keystore
spec:
  serviceAccountName: inventory-sync
  automountServiceAccountToken: true
  containers:
  - name: curl
    image: curlimages/curl:8.17.0
    command: ["sleep", "1d"]
EOF2
k -n keystore wait --for=condition=Ready pod/api-client

k -n keystore exec api-client -- sh -c '
  SA=/var/run/secrets/kubernetes.io/serviceaccount
  curl -s --cacert $SA/ca.crt -H "Authorization: Bearer $(cat $SA/token)" \
    https://kubernetes.default.svc/api/v1/namespaces/keystore/secrets' > {{WORKDIR}}/secrets.json
head -5 {{WORKDIR}}/secrets.json                          # "kind": "SecretList"
```

Because the ServiceAccount sets `automountServiceAccountToken: false`, a pod that only names it gets no token volume; `automountServiceAccountToken: true` in the pod spec wins over the ServiceAccount. The token is a short-lived projected token that the kubelet rotates. The single quotes around the `sh -c` script matter: `$(cat $SA/token)` must run inside the pod, while the `>` redirect outside them writes the file on your host. A `403 Forbidden` (`"kind": "Status"`) means the request was not made as `inventory-sync`, usually because no token was sent and you are `system:anonymous`.
