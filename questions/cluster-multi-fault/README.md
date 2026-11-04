# Four faults at once

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` is broken in four places at once. The nodes are `{{NODE_CP}}` and `{{NODE_W1}}` (`ssh <node>`). Faults can mask each other: re-test after every fix.

**A.** Node `{{NODE_W1}}` is `NotReady`. Fix it so that it is `Ready`, and stays so after the node reboots.

**B.** From a pod, resolving `kubernetes.default.svc.cluster.local` fails. Fix cluster DNS.

**C.** Service `web` in namespace `ops-check` has a Ready backend pod, but nothing answers on its ClusterIP. Fix it so that `wget -qO- http://<ClusterIP of web>` from a pod returns the nginx page.

**D.** The API server writes an audit log. A ServiceAccount in `ops-check` tried to delete the Secret `db-credentials` and was denied by RBAC. Write its full username, exactly as the audit log shows it (`system:serviceaccount:<namespace>:<name>`), into `{{WORKDIR}}/denied-user.txt`.

## Hints

- A: `systemctl status kubelet` and `journalctl -u kubelet` on the node. B and C need a schedulable node, so start with A.
- B: CoreDNS runs as Deployment `coredns` in `kube-system` with its configuration in ConfigMap `coredns`. C: kube-proxy is a DaemonSet with its configuration in ConfigMap `kube-proxy`; read the logs of both.
- C: a ConfigMap change only reaches kube-proxy when its pods restart. `iptables-save | grep ops-check/web` on a node shows whether rules exist.
- D: `grep audit /etc/kubernetes/manifests/kube-apiserver.yaml` names the log file; `jq` is installed on the control plane node. There is more than one denied request.

## Solution

```bash
k config use-context {{CONTEXT}}
```

A: kubelet stopped and disabled.

```bash
k get nodes                                   # {{NODE_W1}} NotReady
ssh {{NODE_W1}}
systemctl status kubelet                      # disabled; inactive (dead)
systemctl enable --now kubelet
exit
k get nodes                                   # Ready after a few seconds
```

B: typo in the cluster domain of the Corefile.

```bash
k -n ops-check run test-dns --image=busybox:1.37 --rm -it --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local      # NXDOMAIN (or a timeout while C is broken)
k -n kube-system get pods -l k8s-app=kube-dns        # Running
k -n kube-system get cm coredns -o yaml | grep kubernetes
# kubernetes cluster.lcoal in-addr.arpa ip6.arpa {   <- must be cluster.local
k -n kube-system edit cm coredns
k -n kube-system rollout restart deploy coredns
k -n kube-system rollout status deploy coredns
```

C: invalid proxy mode in the kube-proxy configuration.

```bash
k -n kube-system get pods -l k8s-app=kube-proxy      # CrashLoopBackOff
k -n kube-system logs -l k8s-app=kube-proxy | tail
# ... KubeProxyConfiguration.Mode.ProxyMode: Invalid value: "iptable" ...
k -n kube-system edit cm kube-proxy                  # mode: iptables
k -n kube-system delete pod -l k8s-app=kube-proxy
k -n kube-system rollout status ds kube-proxy
k -n ops-check run test-web --image=busybox:1.37 --rm -it --restart=Never -- \
  wget -qO- http://$(k -n ops-check get svc web -o jsonpath='{.spec.clusterIP}')
```

D: read the audit log.

```bash
ssh {{NODE_CP}}
grep audit /etc/kubernetes/manifests/kube-apiserver.yaml
# --audit-log-path=/var/log/kubernetes/audit/audit.log
jq -c 'select(.responseStatus.code==403) | [.user.username, .verb, .objectRef.resource, .objectRef.name]' \
  /var/log/kubernetes/audit/audit.log                # a denied get is a red herring
jq -r 'select(.verb=="delete" and .objectRef.resource=="secrets"
              and .objectRef.name=="db-credentials" and .responseStatus.code==403)
       | .user.username' /var/log/kubernetes/audit/audit.log | sort -u
exit
echo "system:serviceaccount:ops-check:<name from the query>" > {{WORKDIR}}/denied-user.txt
```

## Pitfalls

- For a `NotReady` node, `kubectl describe node` shows conditions, not the cause. The cause is in `journalctl -u kubelet` on the node itself.
- `systemctl start` alone fixes the node until the next reboot; the task wants `enable` as well.
- Grepping the audit log for "error" finds nothing: it's JSON. Filter on `.verb`, `.objectRef` and `.responseStatus.code` with `jq`.
