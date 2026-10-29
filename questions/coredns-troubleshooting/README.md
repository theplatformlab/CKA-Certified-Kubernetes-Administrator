# Cluster DNS is down

**Context:** `kubectl config use-context {{CONTEXT}}`

After a maintenance window, applications in namespace `dns-outage` fail with name resolution errors. Pod `shop-frontend` cannot reach Service `stock-api` by name:

```
$ kubectl -n dns-outage exec shop-frontend -- nslookup stock-api
;; connection timed out; no servers could be reached
```

Find the cause and fix it so that pods can resolve cluster Service names and external names again.

Do not delete or recreate any Service in `kube-system`, and do not change the pods' DNS settings.

## Hints

- Cluster DNS is provided by the CoreDNS pods in `kube-system` behind the Service `kube-dns`. Check both: are the pods running, and does the Service have endpoints?
- `k -n kube-system logs deploy/coredns` shows why CoreDNS does not start; its configuration is the ConfigMap `coredns`. Compare the selector of Service `kube-dns` with the labels of the CoreDNS pods.
- There are two faults: the Corefile uses the removed `proxy` plugin (use `forward . /etc/resolv.conf`), and Service `kube-dns` selects `k8s-app=core-dns` instead of `k8s-app=kube-dns`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n kube-system get pods -l k8s-app=kube-dns          # CrashLoopBackOff
k -n kube-system logs deploy/coredns
# plugin/... Corefile:...  Unknown directive 'proxy'
k -n kube-system edit configmap coredns
#   proxy . /etc/resolv.conf {      ->   forward . /etc/resolv.conf {
k -n kube-system rollout restart deployment coredns
k -n kube-system get pods -l k8s-app=kube-dns          # Running, 1/1

k -n dns-outage exec shop-frontend -- nslookup stock-api # still times out
k -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns   # no endpoints
k -n kube-system get svc kube-dns -o jsonpath='{.spec.selector}'            # {"k8s-app":"core-dns"}
k -n kube-system patch svc kube-dns -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'

k -n dns-outage exec shop-frontend -- nslookup stock-api
```

Work from the client towards the server: the pod's `/etc/resolv.conf` points to the ClusterIP of `kube-dns`, the Service needs endpoints, the endpoints are the CoreDNS pods, and those need a valid Corefile. The `proxy` plugin was removed in CoreDNS 1.7; `forward` replaced it. Never recreate `kube-dns` with a new IP: every kubelet passes the old IP (`clusterDNS` in `/var/lib/kubelet/config.yaml`) to every pod.
