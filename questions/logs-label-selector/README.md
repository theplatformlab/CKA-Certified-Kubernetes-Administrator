# Logs of all pods of a Deployment

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `collector` in namespace `ingest` runs {{REPLICAS}} pods with label `app=collector`. Each pod has two containers, `worker` and `shipper`.

1. Save the **complete** logs of container `worker` of all pods with label `app=collector` into `{{WORKDIR}}/worker-all.log`.
2. Save the last `{{TAIL}}` lines of container `shipper` of each of these pods into `{{WORKDIR}}/shipper-tail.log`. Every line must be prefixed with the name of the pod and container it came from, the way `kubectl logs` prefixes them (`[pod/<pod>/<container>] ...`).

## Hints

- `kubectl logs` accepts a label selector (`-l`) instead of a pod name, and `-c` for the container.
- With a selector, `kubectl logs` prints only the last 10 lines per pod unless you set `--tail` yourself.
- `--tail=-1` prints everything, `--tail={{TAIL}}` the last {{TAIL}} lines per container, and `--prefix` adds `[pod/<pod>/<container>]`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n ingest logs -l app=collector -c worker --tail=-1 > {{WORKDIR}}/worker-all.log
wc -l {{WORKDIR}}/worker-all.log                 # {{REPLICAS}} pods x 40 lines
k -n ingest logs -l app=collector -c shipper --tail={{TAIL}} --prefix > {{WORKDIR}}/shipper-tail.log
```

The trap is the default: `kubectl logs <pod>` shows all lines, but `kubectl logs -l <selector>` shows only the last 10 lines of each pod, so the first command without `--tail=-1` silently loses most of the log. `--tail` counts per container, not in total. `kubectl logs deploy/collector` would only show one of the pods. With more than 5 matching pods you would also need `--max-log-requests`.
