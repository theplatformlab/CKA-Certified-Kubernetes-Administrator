# Collect etcd facts from the control plane

**Context:** `kubectl config use-context {{CONTEXT}}`

The security team audits the etcd of cluster `{{CLUSTER}}`. etcd runs as a static pod on `{{NODE_CP}}` (`ssh {{NODE_CP}}`).

Find out the following about the etcd server and write it into `{{WORKDIR}}/etcd-info.txt` on your exam host (not on the node), one line per item, exactly in this format:

```
key_file: <path of the private key etcd uses to serve clients>
cert_expiry: <expiry date of the etcd server certificate, as openssl prints it>
client_cert_auth: <yes or no: does etcd require client certificates>
```

For example: `cert_expiry: Mar  4 09:15:00 2027 GMT`.

## Hints

- Everything etcd is started with is in its static pod manifest on the control plane node.
- `--key-file`, `--cert-file` and `--client-cert-auth` are the flags you need. The `--peer-*` flags are for traffic between etcd members, not for clients.
- `openssl x509 -noout -enddate -in <cert>` prints `notAfter=...`. Copy the part after `=`.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
grep -E -- '--(key-file|cert-file|client-cert-auth)=' /etc/kubernetes/manifests/etcd.yaml
#     - --cert-file=/etc/kubernetes/pki/etcd/server.crt
#     - --client-cert-auth=true
#     - --key-file=/etc/kubernetes/pki/etcd/server.key
openssl x509 -noout -enddate -in /etc/kubernetes/pki/etcd/server.crt
# notAfter=Nov  1 21:09:27 2027 GMT
exit

cat > {{WORKDIR}}/etcd-info.txt <<'TXT'
key_file: /etc/kubernetes/pki/etcd/server.key
cert_expiry: Nov  1 21:09:27 2027 GMT
client_cert_auth: yes
TXT
```

`--cert-file`/`--key-file` are the certificate and key etcd presents to its clients (the kube-apiserver, etcdctl). `--client-cert-auth=true` makes etcd reject every client that has no certificate signed by `--trusted-ca-file`; that is why etcdctl needs `--cacert`, `--cert` and `--key`. kubeadm signs the etcd certificates with its own CA (`/etc/kubernetes/pki/etcd/ca.crt`) for one year. `kubeadm certs check-expiration` lists the same date as `etcd-server`, in its own format.
