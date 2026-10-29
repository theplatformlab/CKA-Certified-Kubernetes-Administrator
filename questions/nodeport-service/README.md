# Expose an application with a NodePort

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `legacy-app` in namespace `legacy` listens on port `3000`.

Create a Service named `legacy-svc` in namespace `legacy`:

- type `NodePort`
- Service port `8080`
- target port `3000`
- node port `30080`

The application must answer on `<any-node-ip>:30080`.

## Hints

- `kubectl expose` copies the Deployment's selector; `kubectl create service` doesn't.
- `port` is the Service port, `targetPort` the container port, `nodePort` the port on every node.
- Test with `wget` against a node's INTERNAL-IP from `kubectl get nodes -o wide`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n legacy expose deploy legacy-app --name=legacy-svc --type=NodePort --port=8080 --target-port=3000 $do > svc.yaml
# add  nodePort: 30080  under spec.ports[0]
k apply -f svc.yaml

k get nodes -o wide                                    # pick an INTERNAL-IP
k run t --rm -it --image=busybox:1.37 --restart=Never -- wget -qO- <node-ip>:30080
```

`kubectl create service nodeport legacy-svc --tcp=8080:3000 --node-port=30080` would select `app=legacy-svc`, which matches nothing here. `expose` copies the Deployment's selector, so prefer it.
