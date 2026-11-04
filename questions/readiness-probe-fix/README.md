# Pods never become ready

**Context:** `kubectl config use-context {{CONTEXT}}`

The pods of Deployment `stock-api` in namespace `inventory` are `Running`, but none of them ever becomes `Ready`, and requests to `http://stock-api.inventory` fail.

Find the cause and fix it so that both pods become ready behind the Service. Keep the readiness probe (as an HTTP probe), the image, the command, the container port and the Service as they are otherwise.

## Hints

- `k -n inventory describe pod -l app=stock-api`: look at the `Readiness` line and the `Warning` events.
- What does the application itself say about its port and health endpoint? `k -n inventory logs deploy/stock-api`.
- Both `path` and `port` of the probe's `httpGet` have to match the application.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n inventory get pods                              # 0/1 Running
k -n inventory describe pod -l app=stock-api | grep -E 'Readiness|Unhealthy'
# Readiness: http-get http://:80/healthz ...
# Readiness probe failed: Get "http://10.244.x.y:80/healthz": connect: connection refused
k -n inventory logs deploy/stock-api
# stock-api listening on :8080, readiness endpoint GET /ready

k -n inventory edit deploy stock-api
```

```yaml
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080        # or: http (the container port's name)
          periodSeconds: 5
          failureThreshold: 3
```

```bash
k -n inventory rollout status deploy stock-api
k -n inventory get endpointslices                    # 2 ready endpoints
```

A failing readiness probe never restarts a container (that's what liveness probes do). It only keeps the pod out of the Service's ready endpoints. So the pods look healthy in `get pods` except for `0/1`, and the Service has no ready backends.
