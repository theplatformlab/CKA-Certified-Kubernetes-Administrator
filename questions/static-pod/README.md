# Static pod on a worker node

**Context:** `kubectl config use-context {{CONTEXT}}`

Create a static pod on node `{{NODE_W1}}` (`ssh {{NODE_W1}}`). Use the static pod directory the kubelet on that node is configured with, and name the manifest file `static-web.yaml`.

- pod name `static-web`, namespace `static-web`, label `app=static-web`
- one container named `web`, image `nginx:1.27`, containerPort `80`

The pod must show up in `kubectl get pods -n static-web` and be Running.

## Hints

- The kubelet's config file names the directory: `grep staticPodPath /var/lib/kubelet/config.yaml` (`systemctl cat kubelet` shows where the config file is).
- `k run static-web --image=nginx:1.27 --port=80 -l app=static-web -n static-web --dry-run=client -o yaml` gives you the manifest; copy it into that directory on the node.
- The API server only shows a read-only mirror pod, named `static-web-{{NODE_W1}}`. It appears only if its namespace exists, so set `namespace:` in the manifest.

## Solution

```bash
k config use-context {{CONTEXT}}
k run static-web --image=nginx:1.27 --port=80 -l app=static-web -n static-web \
  --dry-run=client -o yaml | grep -v -e creationTimestamp -e 'resources: {}' -e '^status'

ssh {{NODE_W1}}
grep staticPodPath /var/lib/kubelet/config.yaml
# staticPodPath: /etc/kubernetes/manifests

cat > /etc/kubernetes/manifests/static-web.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  namespace: static-web
  labels:
    app: static-web
spec:
  containers:
  - name: web
    image: nginx:1.27
    ports:
    - containerPort: 80
YAML
exit

k -n static-web get pods -o wide             # static-web-{{NODE_W1}}  1/1  Running
```

## Pitfalls

- `kubectl delete pod static-web-{{NODE_W1}}` only deletes the mirror pod; the kubelet brings it back a few seconds later. The only way to remove a static pod is to delete its manifest on the node.
- Don't assume `/etc/kubernetes/manifests`: read `staticPodPath` from the kubelet config. A manifest in the wrong directory just never appears.
- The pod name gets the node name appended: search with `k get pods -A | grep static-web`.
