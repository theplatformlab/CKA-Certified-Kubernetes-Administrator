# kubectl debug for a pod and a node

**Context:** `kubectl config use-context {{CONTEXT}}`

1. Pod `dns-cache` in namespace `debugging` runs an image without a shell, so `kubectl exec` is no help. Attach an ephemeral debug container with image `busybox:1.37` that shares the process namespace of the container `dns-cache`. Find out which UID the DNS server process runs as and write the number into `{{WORKDIR}}/dns-uid.txt`. The pod must keep running.
2. A maintenance ticket number was left on node `{{NODE_W1}}` in the file `/etc/cka/maintenance-ticket`. Read it with `kubectl debug` on the node, using image `busybox:1.37` and creating the debugger pod in namespace `debugging`. Write the ticket number into `{{WORKDIR}}/ticket.txt`.

## Hints

- `kubectl debug <pod> -it --image=... --target=<container>` adds an ephemeral container that sees the target's processes. Without `--target` you only see your own shell.
- `ps` in busybox shows the user of each process; `/proc/<pid>/status` has the `Uid:` line.
- `kubectl debug node/<node> -it --image=...` mounts the node's root filesystem at `/host`.

## Solution

```bash
k -n debugging debug dns-cache -it --image=busybox:1.37 --target=dns-cache -- sh
#   ps -o pid,user,args          # PID 1: /coredns ..., user 65532
#   grep Uid /proc/1/status      # Uid: 65532 ...
#   exit
echo 65532 > {{WORKDIR}}/dns-uid.txt

k debug node/{{NODE_W1}} -n debugging -it --image=busybox:1.37
#   cat /host/etc/cka/maintenance-ticket      # or: chroot /host, then cat /etc/cka/...
#   exit
echo <ticket> > {{WORKDIR}}/ticket.txt
```

The ephemeral container stays in the pod spec after you exit (`k -n debugging get pod dns-cache -o jsonpath='{.spec.ephemeralContainers}'`), and the node debugger pod stays in the namespace as `Completed`. Delete it when you are done.

## Pitfalls

- Without `--target` the debug container gets its own process namespace: `ps` shows only busybox, no `coredns`.
- In a node debug session the node is under `/host`. `chroot /host` makes it the root, so node paths and tools (`systemctl`, `crictl`, `journalctl`) work as usual.
