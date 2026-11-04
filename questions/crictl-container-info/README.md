# Inspect a container with crictl

**Context:** `kubectl config use-context {{CONTEXT}}`

The security team is investigating case `{{CASE_ID}}` and needs runtime details of a fresh web container.

1. In namespace `forensics`, create a pod `{{POD}}` with labels `team=forensics` and `case={{CASE_ID}}`. It runs one container named `web` with image `nginx:1.28`.
2. Find out on which node the pod runs. Nodes are reachable with `ssh <node>`.
3. On that node, use `crictl` to find the container `web` of the pod. Write its container ID and its `info.runtimeType` from `crictl inspect` into `{{WORKDIR}}/container-info.txt`, on one line separated by a space:
   ```
   <container-id> <runtimeType>
   ```
4. Write the logs of that container, as `crictl` shows them, into `{{WORKDIR}}/container.log`. Include both stdout and stderr.

`{{WORKDIR}}` is on your host, not on the node.

## Hints

- `k -n forensics get pod {{POD}} -o wide` shows the node.
- `crictl ps` filters with `--name <container>` and `--label io.kubernetes.pod.name=<pod>`; the short ID it prints is enough. `crictl inspect <id>` prints JSON with an `info` section.
- `ssh <node> '<command>'` runs a single command on the node, and its output lands on your host, so you can redirect it into `{{WORKDIR}}` directly. `crictl logs` writes the container's stderr to stderr: redirect both streams (`&>` or `> file 2>&1`).

## Solution

```bash
k config use-context {{CONTEXT}}
cat <<EOF2 | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: {{POD}}
  namespace: forensics
  labels:
    team: forensics
    case: "{{CASE_ID}}"
spec:
  containers:
  - name: web
    image: nginx:1.28
EOF2
k -n forensics get pod {{POD}} -o wide        # NODE: {{NODE_W1}} or {{NODE_W2}}
NODE=$(k -n forensics get pod {{POD}} -o jsonpath='{.spec.nodeName}')

ssh $NODE
crictl ps --name web --label io.kubernetes.pod.name={{POD}}    # CONTAINER 9bfa71c661397 ...
crictl inspect 9bfa71c661397 | grep runtimeType                # "runtimeType": "io.containerd.runc.v2"
exit

CID=$(ssh $NODE "crictl ps -q --name web --label io.kubernetes.pod.name={{POD}}")
TYPE=$(ssh $NODE "crictl inspect $CID" | grep runtimeType | cut -d'"' -f4)
echo "$CID $TYPE" > {{WORKDIR}}/container-info.txt
ssh $NODE "crictl logs $CID" > {{WORKDIR}}/container.log 2>&1
cat {{WORKDIR}}/container-info.txt {{WORKDIR}}/container.log
```

`crictl` talks to the container runtime (containerd) on one node, so it only sees the containers of that node, and it knows nothing about namespaces or pod names except through the labels the kubelet sets (`io.kubernetes.pod.name`, `io.kubernetes.pod.namespace`, `io.kubernetes.container.name`). `crictl ps` prints a 13-character short ID, `-q` the full one; both identify the container. `info.runtimeType` is the containerd shim that runs it, `io.containerd.runc.v2` for runc. nginx prints its entrypoint messages to stdout and its startup notices to stderr; with only `>` the notices end up in your terminal instead of the file. `k -n forensics logs {{POD}}` shows the same lines, read by the kubelet from the same log file on the node.
