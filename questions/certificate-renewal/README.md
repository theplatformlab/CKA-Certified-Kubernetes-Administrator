# Renew control plane certificates

**Context:** `kubectl config use-context {{CONTEXT}}`

The certificates of cluster `{{CLUSTER}}` need to be renewed (`ssh {{NODE_CP}}`).

1. Write the current expiration date of the kube-apiserver serving certificate into `{{WORKDIR}}/expiration.txt` on your exam host (not on the node). Use the same format `kubeadm certs check-expiration` prints, for example `Oct 28, 2027 21:12 UTC`.
2. Renew all certificates with kubeadm.
3. Make sure the running kube-apiserver serves the renewed certificate.

## Hints

- `kubeadm certs check-expiration` shows every certificate and its expiry.
- `kubeadm certs renew all` only rewrites the files.
- The static pods keep the old certificates in memory: restart them by moving the manifests out of `/etc/kubernetes/manifests` and back.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
kubeadm certs check-expiration | grep -w apiserver
# apiserver   Oct 28, 2027 21:12 UTC   364d   ca   no
exit
echo "Oct 28, 2027 21:12 UTC" > {{WORKDIR}}/expiration.txt     # on the exam host

ssh {{NODE_CP}}
kubeadm certs renew all
# "You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd"
mkdir -p /root/manifests-tmp
mv /etc/kubernetes/manifests/*.yaml /root/manifests-tmp/
sleep 20                                     # wait until crictl ps shows them gone
mv /root/manifests-tmp/*.yaml /etc/kubernetes/manifests/
kubeadm certs check-expiration
exit
```

`kubeadm certs renew` only rewrites the files. The static pods keep the old certificates in memory until they restart. Moving the manifests out and back in is the standard way to restart them. `admin.conf` is renewed too, so copy it again if you use it as your kubeconfig.
