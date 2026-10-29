# Exercise 19 — Classic Ingress

> Related: [Ingress skeleton](../../skeletons/ingress.yaml) | [Service skeleton](../../skeletons/service.yaml) | [README — Services and Networking](../../README.md#domain-3--services--networking-20)

Configure Kubernetes Ingress resources for HTTP/HTTPS routing. CKA exam topics include classic Ingress alongside newer Gateway API. This exercise covers path-based routing, TLS termination, and IngressClass configuration.

## Context

Ingress provides external access to services inside a cluster. While Gateway API is the future direction, classic Ingress (networking.k8s.io/v1) appears on most CKA exams. You need to understand:
- How to expose services via Ingress
- Path-based and host-based routing
- TLS certificate setup
- Ingress controller requirements

This differs from Exercise 15 (Gateway API) because it tests the older API that's still in widespread production use.

## Tasks

Work in namespace `exercise-19` (`./scripts/lab.sh setup 19` creates it and an IngressClass `nginx`). The lab cluster runs no Ingress controller, so the check validates the Services (with real traffic) and the Ingress spec.

1. Create two Deployments:
   - `web-app` with image `nginx:1.28` and 2 replicas (nginx listens on port 80)
   - `api-app` with image `nginx:1.28` and 2 replicas (also listens on port 80)
2. Expose `web-app` with a ClusterIP Service named `web-service` on port 80 (targetPort 80)
3. Expose `api-app` with a ClusterIP Service named `api-service` on port 8080, forwarding to the container's port 80
4. Create an Ingress resource named `app-ingress` with `ingressClassName: nginx` that routes:
   - `/` (Prefix) traffic to `web-service:80`
   - `/api` (Prefix) traffic to `api-service:8080`
   - Default backend (no matching path) should point to `web-service:80`
5. Check the Ingress: `ADDRESS` stays empty here because no controller is running (with ingress-nginx installed it gets one)
6. Test path-based routing by describing the Ingress (check rules)

Validate with `./scripts/lab.sh check 19`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k create service clusterip` to create services imperatively
- Ingress requires an Ingress Controller (usually nginx-ingress or similar) to function
- Path-based routing uses `path` with `pathType: Prefix` in Ingress rules
- `k get ingress` shows ingress resources; `k describe ingress` shows routing rules
- Without an Ingress Controller, the Ingress creates successfully but no ADDRESS is assigned
- Exam scenario: You may need to install/verify nginx-ingress controller first

</details>

## What tripped me up

> I created the Ingress but forgot the services. The Ingress created successfully and showed a backend error. The error message "no endpoints available for backend" took me 8 minutes to debug. Now I always create services first, then verify they have endpoints, then create the Ingress.
>
> Path types matter: `Prefix` means any path starting with the rule path matches. `Exact` requires exact match. I used `Exact` and couldn't reach `/api/v1/users` path. Switched to `Prefix` and it worked. Read the pathType documentation carefully.
>
> The Ingress controller needs a LoadBalancer service or NodePort to expose the Ingress externally. In a lab environment without a LoadBalancer provider, the Ingress works but you can't test from outside the cluster. During CKA exam scenarios, the cluster infrastructure is already set up.

## Verify

```bash
./scripts/lab.sh check 19
```

Manual checks:

```bash
# Services have endpoints
k get endpointslices -n exercise-19

# Both Services answer (api-service on 8080 -> pod port 80)
k -n exercise-19 run t --image=busybox:1.37 --rm -it --restart=Never -- \
  sh -c 'wget -qO- web-service:80 | head -4; wget -qO- api-service:8080 | head -4'

# Ingress rules, class and default backend
k get ingress -n exercise-19
k describe ingress app-ingress -n exercise-19
k get ingress app-ingress -n exercise-19 -o yaml
```

## Cleanup

```bash
./scripts/lab.sh cleanup 19
```

<details>
<summary>Solution</summary>

```bash
# Deployments
k create deployment web-app -n exercise-19 --image=nginx:1.28 --replicas=2
k create deployment api-app -n exercise-19 --image=nginx:1.28 --replicas=2

# Wait for pods
k rollout status deployment web-app -n exercise-19
k rollout status deployment api-app -n exercise-19

# Services (nginx listens on 80 in both Deployments; api-service exposes it as 8080)
k expose deployment web-app -n exercise-19 --name=web-service --type=ClusterIP --port=80 --target-port=80
k expose deployment api-app -n exercise-19 --name=api-service --type=ClusterIP --port=8080 --target-port=80

# Verify endpoints exist
k get endpointslices -n exercise-19

# Ingress YAML definition
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: exercise-19
spec:
  ingressClassName: nginx
  defaultBackend:
    service:
      name: web-service
      port:
        number: 80
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
EOF

# Verify Ingress was created
k get ingress -n exercise-19
k describe ingress app-ingress -n exercise-19

# Imperative alternative (/api* creates path /api, Prefix):
# k create ingress app-ingress -n exercise-19 --class=nginx \
#   --rule="/*=web-service:80" --rule="/api*=api-service:8080" --default-backend=web-service:80

# Note: ADDRESS will remain empty if no ingress controller is running
# In a real cluster with nginx-ingress installed, it would show the external IP/hostname
```

</details>
