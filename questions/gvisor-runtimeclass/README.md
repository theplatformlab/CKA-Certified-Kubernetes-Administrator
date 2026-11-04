# Run a Deployment in the gVisor sandbox

**Context:** `kubectl config use-context {{CONTEXT}}`

The container runtime on node `{{NODE_W1}}` has a handler `runsc` that runs containers in the gVisor sandbox.

1. Create a RuntimeClass `{{RC}}` that uses this handler.
2. Change Deployment `file-parser` in namespace `sandboxed-apps` so that its Pods run with this RuntimeClass. Both replicas must be ready.
3. Write the output of `dmesg` from one of the new Pods into `{{WORKDIR}}/gvisor-dmesg.txt` on your exam host.

## Hints

- The RuntimeClass page on kubernetes.io has an example. A RuntimeClass is cluster-scoped and has only `handler` (plus optional `overhead` and `scheduling`).
- Pods select it with `spec.runtimeClassName`.
- Inside gVisor, `dmesg` shows the sandbox's own kernel messages (`Starting gVisor...`), not the host's.

## Solution

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: {{RC}}
handler: runsc
```

```bash
k config use-context {{CONTEXT}}
k apply -f runtimeclass.yaml
k -n sandboxed-apps patch deploy file-parser -p '{"spec":{"template":{"spec":{"runtimeClassName":"{{RC}}"}}}}'
k -n sandboxed-apps rollout status deploy file-parser
k -n sandboxed-apps exec deploy/file-parser -- dmesg > {{WORKDIR}}/gvisor-dmesg.txt
cat {{WORKDIR}}/gvisor-dmesg.txt      # [    0.000000] Starting gVisor...
k -n sandboxed-apps exec deploy/file-parser -- uname -r     # gVisor's kernel version, not the node's
```

The handler name has to match the runtime name in the containerd configuration (`/etc/containerd/config.toml` on the node, section `...containerd.runtimes.runsc`). If no node can run the handler, the Pods fail with `no runtime for "runsc" is configured`. gVisor intercepts the containers' syscalls in a user-space kernel, so a kernel exploit in the container doesn't reach the host kernel directly.
