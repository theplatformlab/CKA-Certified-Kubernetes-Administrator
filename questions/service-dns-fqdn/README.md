# Service discovery and DNS

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `portal` contains a Service `web-ui` on port `3000`. An application in namespace `orders` needs to reach it.

1. Write the fully qualified DNS name of Service `web-ui` into `{{WORKDIR}}/dns.txt` (only the name).
2. Create a pod named `dns-test` in namespace `orders` with image `busybox:1.37` and command `sleep 3600`.
3. Use `dns-test` to resolve the Service's name with `nslookup`. Save the complete output to `{{WORKDIR}}/nslookup.txt`.

## Hints

- Service DNS names follow `<service>.<namespace>.svc.<cluster-domain>`.
- `kubectl run ... --command -- sleep 3600` gives you a pod to exec into.
- `kubectl exec <pod> -- nslookup <name> > file` writes the output on your host.

## Solution

```bash
k config use-context {{CONTEXT}}
echo web-ui.portal.svc.cluster.local > {{WORKDIR}}/dns.txt

k -n orders run dns-test --image=busybox:1.37 --command -- sleep 3600
k -n orders wait --for=condition=Ready pod/dns-test
k -n orders exec dns-test -- nslookup web-ui.portal.svc.cluster.local > {{WORKDIR}}/nslookup.txt
cat {{WORKDIR}}/nslookup.txt
```

The pattern is `<service>.<namespace>.svc.<cluster-domain>`, and the cluster domain is `cluster.local` unless the kubelet sets it otherwise (`clusterDomain` in `/var/lib/kubelet/config.yaml`). Inside the same namespace, `web-ui` alone works. From another namespace, `web-ui.portal` works too, thanks to the search domains in the pod's `/etc/resolv.conf`.
