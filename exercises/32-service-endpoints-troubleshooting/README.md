# Exercise 32 — Troubleshoot a Service

> **Medium** | ~15 min | Domain: Services & Networking (20%)
>
> Related: [Service skeleton](../../skeletons/service.yaml) | [Exercise 11 — Troubleshoot Cluster](../11-troubleshoot-cluster/)

Clients can't reach the `payments` application through its ClusterIP Service. Find the cause, fix it, and verify DNS and HTTP access from a test Pod.

## Current state

Namespace `exercise-32` contains the Deployment `payments` (`nginx:1.28`, 2 replicas), the ClusterIP Service `payments` (port 80) and the test Pod `netcheck` (`busybox:1.37`) (`./scripts/lab.sh setup 32` creates them). Something in it is broken — that is the task.

## Tasks

Work in namespace `exercise-32`.

1. From `netcheck`, an HTTP request to `payments.exercise-32.svc.cluster.local` (port 80) must succeed, served by both replicas.
2. Fix the cause without changing the Deployment.

Validate with `./scripts/lab.sh check 32`.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Does the Service have endpoints? `k get endpointslices -n exercise-32 -l kubernetes.io/service-name=payments`
- Start with `k get svc payments -n exercise-32 -o yaml` and `k get pods -n exercise-32 --show-labels`.
- A Service selector must match the Pod labels exactly.
- If endpoints exist but the request still fails, compare `port`, `targetPort`, and the port the application listens on.

</details>

## Verify

```bash
./scripts/lab.sh check 32
```

Manual checks:

```bash
# The EndpointSlice should list two ready endpoints
k get endpointslices -n exercise-32 \
  -l kubernetes.io/service-name=payments -o wide

# DNS should resolve to the Service ClusterIP
k exec netcheck -n exercise-32 -- \
  nslookup payments.exercise-32.svc.cluster.local

# The Service should return the nginx welcome page
k exec netcheck -n exercise-32 -- \
  wget -qO- -T 3 http://payments.exercise-32.svc.cluster.local
```

## Optional Challenge

After the main task works, change the Service `targetPort` to `8080`. Check whether EndpointSlices still contain ready endpoints, then diagnose why the HTTP request fails. Restore `targetPort: 80` afterward — the check expects port 80 -> targetPort 80.

## Cleanup

```bash
./scripts/lab.sh cleanup 32
```

<details>
<summary>Solution</summary>

The Deployment Pods have the label `app=payments`, but the Service selector is `app=payment`. Because the selector does not match, the Service has no ready endpoints.

Check both sides:

```bash
k get service payments -n exercise-32 -o yaml
k get pods -n exercise-32 --show-labels
k get endpointslices -n exercise-32 \
  -l kubernetes.io/service-name=payments -o wide
```

Update the Service selector to match the Pods:

```bash
k patch service payments -n exercise-32 --type=merge \
  -p '{"spec":{"selector":{"app":"payments"}}}'
```

Wait for both ready Pod IPs to appear in the EndpointSlice, then verify name resolution and HTTP access:

```bash
k get endpointslices -n exercise-32 \
  -l kubernetes.io/service-name=payments -o wide
k exec netcheck -n exercise-32 -- \
  nslookup payments.exercise-32.svc.cluster.local
k exec netcheck -n exercise-32 -- \
  wget -qO- -T 3 http://payments.exercise-32.svc.cluster.local
```

For the optional challenge, the selector still matches and endpoints remain present, but port `8080` has no listener in the nginx container. Restore `targetPort` to `80`.

</details>