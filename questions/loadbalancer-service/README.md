# Service of type LoadBalancer

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `{{APP}}` in namespace `edge-lb` runs a web server on container port `80`. The cluster has a cloud controller that provisions external load balancers.

1. Expose the Deployment with a Service named `{{APP}}-lb` of type `LoadBalancer` in namespace `edge-lb`:
   - Service port `{{LB_PORT}}` (TCP), forwarding to container port `80`
   - node port `{{NODE_PORT}}`
2. Wait until the Service has an external IP and write that IP (only the address) into `{{WORKDIR}}/lb-ip.txt`.
3. Check that `http://<external-ip>:{{LB_PORT}}/` answers with the app's page.

## Hints

- `kubectl expose` can create a Service of any type for an existing Deployment.
- `k -n edge-lb expose deploy {{APP}} --name={{APP}}-lb --type=LoadBalancer --port={{LB_PORT}} --target-port=80` creates it. `expose` cannot set the node port, so add `nodePort` afterwards with `k edit` or write the YAML with `$do`.
- The external IP shows up in `k -n edge-lb get svc {{APP}}-lb` (column `EXTERNAL-IP`, `<pending>` until the controller is done) and in `.status.loadBalancer.ingress[0].ip`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n edge-lb expose deploy {{APP}} --name={{APP}}-lb --type=LoadBalancer \
  --port={{LB_PORT}} --target-port=80 $do > lb.yaml
```

Add the node port to the port entry:

```yaml
  ports:
  - port: {{LB_PORT}}
    protocol: TCP
    targetPort: 80
    nodePort: {{NODE_PORT}}
```

```bash
k apply -f lb.yaml
k -n edge-lb get svc {{APP}}-lb -w                     # until EXTERNAL-IP is set
k -n edge-lb get svc {{APP}}-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' > {{WORKDIR}}/lb-ip.txt
curl -s http://$(cat {{WORKDIR}}/lb-ip.txt):{{LB_PORT}}/
```

A LoadBalancer Service is a NodePort Service plus an external address: Kubernetes allocates the ClusterIP and the node port, and the cloud controller (here cloud-provider-kind) provisions the load balancer and writes its address into `.status.loadBalancer`. Without a cloud controller, `EXTERNAL-IP` stays `<pending>` forever. The load balancer listens on the Service `port`, not on the node port.
