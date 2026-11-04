# Startup, liveness and readiness probes

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `orders-api` in namespace `health-api` needs about 15 seconds to start and then serves HTTP on port `{{PORT}}`. It has no health checks yet. Add these probes to its container:

- **startup probe:** TCP connection to port `{{PORT}}`, every `5` seconds, at most `{{START_FAIL}}` failures
- **liveness probe:** HTTP GET `/healthz` on port `{{PORT}}`, every `{{LIVE_PERIOD}}` seconds, timeout `2` seconds, failure threshold `3`
- **readiness probe:** runs the command `cat /tmp/ready`, every `5` seconds

Do not change the image or the command. Both replicas must become Ready without any container restart.

## Hints

- The fields are `startupProbe`, `livenessProbe` and `readinessProbe` on the container, with `tcpSocket`, `httpGet` and `exec` handlers.
- `k explain deploy.spec.template.spec.containers.livenessProbe` lists `periodSeconds`, `timeoutSeconds`, `failureThreshold`.
- Liveness and readiness probes only start once the startup probe has succeeded, so no `initialDelaySeconds` is needed.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n health-api edit deploy orders-api
```

```yaml
      containers:
      - name: api
        image: busybox:1.37
        command: [...]                      # unchanged
        ports:
        - containerPort: {{PORT}}
        startupProbe:
          tcpSocket:
            port: {{PORT}}
          periodSeconds: 5
          failureThreshold: {{START_FAIL}}
        livenessProbe:
          httpGet:
            path: /healthz
            port: {{PORT}}
          periodSeconds: {{LIVE_PERIOD}}
          timeoutSeconds: 2
          failureThreshold: 3
        readinessProbe:
          exec:
            command: ["cat", "/tmp/ready"]
          periodSeconds: 5
```

```bash
k -n health-api rollout status deploy orders-api
k -n health-api get pods -l app=orders-api        # 1/1 Running, RESTARTS 0
k -n health-api describe pod -l app=orders-api | grep -E 'Startup|Liveness|Readiness'
```

The startup probe gives the app up to 5 × {{START_FAIL}} seconds to come up; until then the liveness probe is not run, so a slow start never ends in a restart loop. A failing liveness probe restarts the container, a failing readiness probe only takes the pod out of the Service endpoints.
