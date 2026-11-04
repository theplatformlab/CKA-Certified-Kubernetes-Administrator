# User certificate and kubeconfig

**Context:** `kubectl config use-context {{CONTEXT}}`

A new team member, `{{CSR_USER}}`, needs read access to namespace `insights` with a client certificate. Work on your exam host and put all files into `{{WORKDIR}}/`.

1. Create a 2048-bit RSA private key `{{WORKDIR}}/{{CSR_USER}}.key` and a certificate signing request for the user name `{{CSR_USER}}`.
2. Submit it as a CertificateSigningRequest named `{{CSR_USER}}` for client authentication against the API server, approve it, and save the issued certificate as `{{WORKDIR}}/{{CSR_USER}}.crt` (PEM).
3. Create the kubeconfig file `{{WORKDIR}}/{{CSR_USER}}.kubeconfig`. It must work on its own: it contains the cluster (same API server and CA as context `{{CONTEXT}}`), the user `{{CSR_USER}}` with the embedded certificate and key, and a current context with default namespace `insights`.
4. In namespace `insights`, create a Role `insights-reader` that allows exactly `{{VERBS}}` on `pods` and `{{RESOURCE}}`, and a RoleBinding `insights-reader` that grants it to `{{CSR_USER}}`.

## Hints

- `openssl genrsa` creates the key and `openssl req -new -subj "/CN=..."` the CSR. The CN becomes the Kubernetes user name.
- The CertificateSigningRequest needs `signerName: kubernetes.io/kube-apiserver-client`, `usages: [client auth]` and the base64-encoded CSR (`base64 -w0`) in `spec.request`. Then `k certificate approve`, and the certificate is in `.status.certificate` (base64).
- Build the kubeconfig with `k config ... --kubeconfig=<file>`: `set-cluster` (`--server`, `--certificate-authority` + `--embed-certs`), `set-credentials` (`--client-certificate`, `--client-key`, `--embed-certs`), `set-context` (`--namespace`) and `use-context`. Test with `k --kubeconfig <file> auth whoami`.

## Solution

```bash
k config use-context {{CONTEXT}}
cd {{WORKDIR}}
openssl genrsa -out {{CSR_USER}}.key 2048
openssl req -new -key {{CSR_USER}}.key -subj "/CN={{CSR_USER}}" -out {{CSR_USER}}.csr

cat <<EOF2 | k apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: {{CSR_USER}}
spec:
  request: $(base64 -w0 < {{CSR_USER}}.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF2
k certificate approve {{CSR_USER}}
k get csr {{CSR_USER}} -o jsonpath='{.status.certificate}' | base64 -d > {{CSR_USER}}.crt

# cluster data of the current context
k config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
SERVER=$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')

KC={{CSR_USER}}.kubeconfig
k config set-cluster {{CLUSTER}} --server=$SERVER --certificate-authority=ca.crt --embed-certs --kubeconfig=$KC
k config set-credentials {{CSR_USER}} --client-certificate={{CSR_USER}}.crt --client-key={{CSR_USER}}.key --embed-certs --kubeconfig=$KC
k config set-context {{CSR_USER}}@{{CLUSTER}} --cluster={{CLUSTER}} --user={{CSR_USER}} --namespace=insights --kubeconfig=$KC
k config use-context {{CSR_USER}}@{{CLUSTER}} --kubeconfig=$KC

k -n insights create role insights-reader --verb={{VERBS}} --resource=pods,{{RESOURCE}}
k -n insights create rolebinding insights-reader --role=insights-reader --user={{CSR_USER}}

k --kubeconfig=$KC auth whoami          # {{CSR_USER}}
k --kubeconfig=$KC get pods             # works (namespace insights)
k --kubeconfig=$KC get pods -n default  # Forbidden
```

Kubernetes has no user objects. A user is whoever presents a certificate signed by the cluster CA: the CN is the user name and every O is a group. `--embed-certs` copies the files into the kubeconfig as `*-data` fields, so the file keeps working when it is moved. Without it, the kubeconfig only holds paths. `kubectl --kubeconfig` replaces the `KUBECONFIG` environment variable, so the test really uses only the new file.
