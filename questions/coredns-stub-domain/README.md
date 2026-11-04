# Forward a private DNS zone in CoreDNS

**Context:** `kubectl config use-context {{CONTEXT}}`

The company runs an internal DNS server for the zone `corp.internal`. In this cluster it is reachable through the Service `corp-dns` in namespace `corp-dns` (port `53`, UDP and TCP). Pods currently cannot resolve names like `{{HOST}}.corp.internal`.

1. Configure the cluster DNS (CoreDNS in namespace `kube-system`) so that every pod can resolve names in the zone `corp.internal`. Queries for this zone must be answered by the `corp-dns` server.
2. Cluster-internal names (e.g. `kubernetes.default.svc.cluster.local`) and all other names must keep resolving as before.

Do not modify anything in namespace `corp-dns`.

## Hints

- CoreDNS reads its configuration (the Corefile) from the ConfigMap `coredns` in `kube-system`. The `reload` plugin picks up changes within about a minute.
- A Corefile can contain several server blocks; a block `corp.internal:53 { ... }` only handles that zone. The `forward` plugin sends queries to upstream servers, and it needs IP addresses, not names.
- Add a server block `corp.internal:53 { errors; cache 30; forward . <ClusterIP of Service corp-dns> }` (one directive per line) next to the existing `.:53` block.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n corp-dns get svc corp-dns                  # note the CLUSTER-IP, e.g. 10.96.123.45
k -n kube-system edit configmap coredns
```

Add a second server block below the existing `.:53 { ... }` block, with the ClusterIP of `corp-dns`:

```
corp.internal:53 {
    errors
    cache 30
    forward . 10.96.123.45
}
```

```bash
k -n kube-system rollout restart deployment coredns       # optional, reload does it within ~1 min
k run dnstest --rm -it --image=busybox:1.37 --restart=Never -- nslookup {{HOST}}.corp.internal
# Address: {{HOST_IP}}
```

CoreDNS picks the server block with the most specific matching zone, so queries for `*.corp.internal` go to the new block and everything else still goes to `.:53` (cluster names via the `kubernetes` plugin, the rest to `/etc/resolv.conf`). Putting a second `forward` into the `.:53` block does not work: each plugin may appear only once per server block. `forward` takes addresses, so use the Service's ClusterIP; a Service name would have to be resolved by CoreDNS itself.
