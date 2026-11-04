# Pod with labels and resources

**Context:** `kubectl config use-context {{CONTEXT}}`

In namespace `webshop`:

1. Create a pod named `web` with image `nginx:1.27` and the labels `app=web` and `tier=frontend`. Its container requests `100m` CPU and `{{MEM_REQ}}` memory and is limited to `{{CPU_LIM}}` CPU and `{{MEM_LIM}}` memory. The pod must be Running.
2. Write the pod's IP address into `{{WORKDIR}}/web-ip.txt`.
3. Without recreating the pod, add the label `version={{VERSION}}` and remove the label `tier`.

## Hints

- `kubectl run` has no flags for requests and limits: generate the YAML with `$do`, then add `resources` to the container.
- `kubectl get pod -o wide` shows the IP; `-o jsonpath='{.status.podIP}'` prints only the IP.
- `kubectl label pod <name> key=value` adds a label, `kubectl label pod <name> key-` removes one.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n webshop run web --image=nginx:1.27 --labels=app=web,tier=frontend $do > web.yaml
```

Add the resources to the container in `web.yaml`:

```yaml
    resources:
      requests:
        cpu: 100m
        memory: {{MEM_REQ}}
      limits:
        cpu: {{CPU_LIM}}
        memory: {{MEM_LIM}}
```

```bash
k apply -f web.yaml
k -n webshop get pod web -o wide
k -n webshop get pod web -o jsonpath='{.status.podIP}' > {{WORKDIR}}/web-ip.txt

k -n webshop label pod web version={{VERSION}}
k -n webshop label pod web tier-
k -n webshop get pod web --show-labels
```

## Pitfalls

- Forgetting `-n webshop` on `k apply` creates the pod in `default`: the grader only looks in the given namespace.
- Don't fight `kubectl run` over resources: redirect `$do` to a file, edit, apply.
