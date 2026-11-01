# Serve Services under an extra DNS domain

**Context:** `kubectl config use-context {{CONTEXT}}`

A legacy application expects Service names under the domain `{{DOMAIN}}` instead of `cluster.local`. The cluster DNS is CoreDNS in namespace `kube-system`.

1. Back up the current CoreDNS configuration (the ConfigMap `coredns` in `kube-system`) to `{{WORKDIR}}/coredns-backup.yaml`. It must be possible to restore the configuration later with `kubectl apply -f {{WORKDIR}}/coredns-backup.yaml`, also after the ConfigMap has been changed.
2. Configure CoreDNS so that `SERVICE.NAMESPACE.svc.{{DOMAIN}}` resolves to the same address as `SERVICE.NAMESPACE.svc.cluster.local`, for every Service. Names under `cluster.local` must keep working.

The Service `invoices` in namespace `accounting` can be used for testing: `invoices.accounting.svc.{{DOMAIN}}` must resolve to its ClusterIP.

## Hints

- `k -n kube-system get configmap coredns -o yaml` contains server-managed fields such as `resourceVersion`, `uid` and `creationTimestamp`. A `resourceVersion` in the file makes `kubectl apply` fail with a conflict as soon as the ConfigMap has changed.
- The `kubernetes` plugin line in the Corefile lists the zones it is authoritative for. It accepts more than one.
- Add `{{DOMAIN}}` after `cluster.local` in the `kubernetes` line. The `reload` plugin applies the change within about a minute, `k -n kube-system rollout restart deploy coredns` right away.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n kube-system get configmap coredns -o yaml > {{WORKDIR}}/coredns-backup.yaml
vim {{WORKDIR}}/coredns-backup.yaml
#   delete resourceVersion, uid and creationTimestamp under metadata
#   (keep name: coredns and namespace: kube-system)
k apply --dry-run=server -f {{WORKDIR}}/coredns-backup.yaml     # the restore would work

k -n kube-system edit configmap coredns
```

Add the domain to the zones of the `kubernetes` plugin:

```
    kubernetes cluster.local {{DOMAIN}} in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
```

```bash
k -n kube-system rollout restart deployment coredns       # optional, reload does it within ~1 min
k -n kube-system rollout status deployment coredns
k run dnstest --rm -it --image=busybox:1.37 --restart=Never -- \
  nslookup invoices.accounting.svc.{{DOMAIN}}
k -n accounting get svc invoices                            # same ClusterIP
```

`k get -o yaml` writes the `resourceVersion` the object had at that moment. `kubectl apply` sends it along, the API server treats it as a precondition and rejects the restore with `the object has been modified` once the ConfigMap has changed, which is exactly when you need the backup. With several zones the `kubernetes` plugin answers `invoices.accounting.svc.{{DOMAIN}}` from the same Service data as `cluster.local`. The `rewrite` plugin (`rewrite name suffix .svc.{{DOMAIN}}. .svc.cluster.local. answer auto`) would work too. To restore: `k apply -f {{WORKDIR}}/coredns-backup.yaml`.
