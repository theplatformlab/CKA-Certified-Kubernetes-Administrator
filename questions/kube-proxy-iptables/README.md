# Inspect the iptables rules of a Service

**Context:** `kubectl config use-context {{CONTEXT}}`

You want to see how kube-proxy implements a ClusterIP Service on node `{{NODE_W1}}` (`ssh {{NODE_W1}}`). Save all files on the machine you are working on, not on the node.

1. Find out which proxy mode kube-proxy uses in this cluster and write it (one word, e.g. `ipvs`) into `{{WORKDIR}}/proxy-mode.txt`.
2. In namespace `traffic-lab`, create a pod `{{SVC}}` with image `nginx:1.28` and a ClusterIP Service `{{SVC}}` that forwards port `{{PORT}}` to port `80` of this pod.
3. Save the rules that kube-proxy created on `{{NODE_W1}}` for this Service, and only those, to `{{WORKDIR}}/rules-before.txt`.
4. Delete the Service (keep the pod). Run the same command again and save its output to `{{WORKDIR}}/rules-after.txt`. It must be empty, which proves that kube-proxy removed the rules.

## Hints

- kube-proxy reads its settings from the ConfigMap `kube-proxy` in `kube-system`; its logs also name the proxier it uses.
- `k expose pod <pod> --port=<service port> --target-port=<container port>` creates the Service. In iptables mode, `iptables-save` on the node lists the rules (table `nat`).
- kube-proxy adds the comment `<namespace>/<service>` to every rule of a Service: `ssh {{NODE_W1}} iptables-save | grep 'traffic-lab/{{SVC}}' > {{WORKDIR}}/rules-before.txt`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | grep '^mode'   # mode: iptables
k -n kube-system logs ds/kube-proxy | grep -i proxier                                    # "Using iptables Proxier"
echo iptables > {{WORKDIR}}/proxy-mode.txt

k -n traffic-lab run {{SVC}} --image=nginx:1.28
k -n traffic-lab expose pod {{SVC}} --port={{PORT}} --target-port=80
k -n traffic-lab get svc,ep {{SVC}}

ssh {{NODE_W1}} iptables-save | grep 'traffic-lab/{{SVC}}' > {{WORKDIR}}/rules-before.txt
cat {{WORKDIR}}/rules-before.txt

k -n traffic-lab delete svc {{SVC}}
ssh {{NODE_W1}} iptables-save | grep 'traffic-lab/{{SVC}}' > {{WORKDIR}}/rules-after.txt
cat {{WORKDIR}}/rules-after.txt          # empty
```

The rules form a chain: `KUBE-SERVICES` matches the ClusterIP and port `{{PORT}}` and jumps to a `KUBE-SVC-...` chain, which picks one `KUBE-SEP-...` chain per endpoint (with several pods by probability), and that one DNATs to `<pod IP>:80`. kube-proxy writes the same rules on every node, because the ClusterIP is translated on the node where the client pod runs. kind uses `iptables` mode by default; in `nftables` mode (`mode: nftables`) the rules live in the `kube-proxy` table of `nft list ruleset`, in `ipvs` mode `ipvsadm -Ln` shows the virtual servers. An empty `mode` in the configuration also means iptables on Linux.
