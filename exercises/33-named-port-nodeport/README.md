# Exercise 33 — Named Container Ports and NodePort

> **Medium** | ~15 min | Domain: Services & Networking (20%)
>
> Related: [Service skeleton](../../skeletons/service.yaml) | [Exercise 19 — Classic Ingress](../19-ingress-classic/)

A catalog Deployment is running, but its container port is not named and it is not exposed outside the cluster. Fix the Pod template and create a NodePort Service that references the named port.

## Lab Requirements

- Cluster: single-node kind or Minikube
- Components: none beyond the Kubernetes service implementation
- Access: permission to create namespaces, Deployments, Pods, and Services
- Test record: Not tested

## Setup

Create the namespace and initial Deployment:

```bash
k create namespace exercise-33
k create deployment catalog --image=nginx:1.28 --replicas=2 -n exercise-33
k rollout status deployment/catalog -n exercise-33 --timeout=90s
```

The Deployment container listens on port 80, but the container port is not declared and there is no named port yet.

## Tasks

1. Inspect the catalog Deployment and confirm its container has no named port.
2. Patch the Pod template to add a named container port:
   - Name: `web`
   - Container port: `80`
   - Protocol: `TCP`
3. Create a Service named `catalog-svc` with:
   - Type: `NodePort`
   - Port: `80`
   - Target port: named port `web`
   - NodePort: `30080`
4. Verify the rollout completes and the Service endpoints contain both ready Pod IPs.
5. Test the Service from inside the cluster and, if the lab network permits, through `<node-ip>:30080`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Container port declaration is metadata for named references; the container must still listen on the matching port.
- Use `k patch deployment catalog -n exercise-33 --type='strategic' -p '{...}'`.
- In the Service, `targetPort: web` matches the container port name `web`.
- With a NodePort Service, `port` is the cluster Service port and `nodePort` is the node-facing port.

</details>

## Verify

```bash
# Named port should appear in the Deployment Pod template
k get deployment catalog -n exercise-33 \
  -o jsonpath='{.spec.template.spec.containers[0].ports}'

# Service should reference the named target port
k get service catalog-svc -n exercise-33 -o yaml

# Ready endpoints should exist
k get endpointslices -n exercise-33 \
  -l kubernetes.io/service-name=catalog-svc

# Test from inside the cluster
k run catalog-check -n exercise-33 --rm -i --restart=Never \
  --image=busybox:1.36 -- wget -qO- -T 3 http://catalog-svc:80

# Optional: test through a node IP
k get nodes -o wide
# curl http://<node-ip>:30080
```

## Cleanup

```bash
k delete namespace exercise-33
```

<details>
<summary>Solution</summary>

Patch the Deployment to add the named container port:

```bash
k patch deployment catalog -n exercise-33 --type='strategic' -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"catalog",
    "ports":[{"name":"web","containerPort":80,"protocol":"TCP"}]
  }]}}}
}'

k rollout status deployment/catalog -n exercise-33 --timeout=90s
```

Create the NodePort Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: catalog-svc
  namespace: exercise-33
spec:
  type: NodePort
  selector:
    app: catalog
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: web
    nodePort: 30080
```

Apply and verify:

```bash
k apply -f catalog-svc.yaml
k get endpointslices -n exercise-33 \
  -l kubernetes.io/service-name=catalog-svc
k run catalog-check -n exercise-33 --rm -i --restart=Never \
  --image=busybox:1.36 -- wget -qO- -T 3 http://catalog-svc:80
```

`targetPort: web` resolves to the named container port `web:80`. A named target port is especially useful when the container port name is stable but the numeric value needs to change.

</details>
