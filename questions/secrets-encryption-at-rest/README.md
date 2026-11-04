# Encrypt Secrets at rest

**Context:** `kubectl config use-context {{CONTEXT}}`

The Secrets of cluster `{{CLUSTER}}` are stored in etcd in plain text (base64 is not encryption): anyone with a copy of the etcd data or a backup can read them. Enable encryption at rest on the kube-apiserver of `{{NODE_CP}}` (`ssh {{NODE_CP}}`):

1. Create an EncryptionConfiguration at `/etc/kubernetes/enc/encryption.yaml` that encrypts the resource `secrets` with the `{{PROVIDER}}` provider, using a key named `key1` with a random 32-byte key you generate. Secrets that are still unencrypted must stay readable.
2. Configure the kube-apiserver to use it. The API server must be running again afterwards.
3. Make sure **all** existing Secrets in all namespaces are stored encrypted, not just new ones.
4. Verify with `etcdctl` on the node that Secret `bank-api` in namespace `treasury` is no longer stored in plain text.

## Hints

- The kubernetes.io page "Encrypting Confidential Data at Rest" has a complete EncryptionConfiguration. The first provider in the list encrypts new writes; the others are only used to read. `identity: {}` (no encryption) at the end keeps the old plain-text Secrets readable.
- `head -c 32 /dev/urandom | base64` generates a suitable key. The flag is `--encryption-provider-config`, and the directory needs a hostPath volume and volumeMount in the static pod manifest.
- The API server encrypts a Secret only when it writes it: `k get secrets -A -o json | k replace -f -` rewrites all of them. etcd keys are `/registry/secrets/<namespace>/<name>`; the etcd certificates are in `/etc/kubernetes/pki/etcd/`.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
mkdir -p /etc/kubernetes/enc
KEY=$(head -c 32 /dev/urandom | base64)
cat > /etc/kubernetes/enc/encryption.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - {{PROVIDER}}:
      keys:
      - name: key1
        secret: $KEY
  - identity: {}
EOF
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --encryption-provider-config=/etc/kubernetes/enc/encryption.yaml
    # ... existing flags ...
    volumeMounts:
    - name: enc
      mountPath: /etc/kubernetes/enc
      readOnly: true
    # ... existing mounts ...
  volumes:
  - name: enc
    hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
  # ... existing volumes ...
```

```bash
watch crictl ps --name kube-apiserver          # wait for the new container (30-60s)
exit

k get secrets -A -o json | k replace -f -      # rewrite every Secret -> now encrypted

ssh {{NODE_CP}}
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/treasury/bank-api | xxd | head      # or: | hexdump -C | head
# 00000000: 2f72 6567 6973 7472 792f 7365 6372 6574  /registry/secret
# 00000010: 732f 7472 6561 7375 7279 2f62 616e 6b2d  s/treasury/bank-
# 00000020: 6170 690a 6b38 733a 656e 633a ....       api.k8s:enc:{{PROVIDER}}:v1:key1:...
```

Before the change the value starts with `k8s\x00` and the Secret's data is readable in the dump; afterwards it starts with `k8s:enc:{{PROVIDER}}:v1:key1:` followed by ciphertext. The order of the providers matters: with `identity` first, the API server would keep writing plain text and only use `{{PROVIDER}}` for reading. Without `identity` in the list, the API server could not read the Secrets that were written before the change until they are re-encrypted. Encryption only happens on write, so step 3 (`replace` of every Secret) is what protects the existing data. Keep the key file safe: whoever has the etcd data and this file can decrypt everything (a KMS provider keeps the key outside the node).
