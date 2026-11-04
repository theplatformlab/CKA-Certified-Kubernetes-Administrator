# Headless and ExternalName Services

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `lookup` runs Deployment `search` ({{REPLICAS}} replicas, pod label `app=search`, container port `9200`). Namespace `datastore` has a Service `postgres` on port `5432`.

In namespace `lookup`:

1. Create a headless Service named `search-headless` for the `search` pods on port `9200`, so that a DNS lookup of `search-headless.lookup.svc.cluster.local` returns the IP addresses of all `search` pods.
2. Create a Service named `{{EXT_NAME}}` of type `ExternalName` so that pods in `lookup` can use the name `{{EXT_NAME}}` to reach Service `postgres` in namespace `datastore`. Point it at the fully qualified name of that Service.
3. Verify both with `nslookup` from a pod in `lookup` (image `busybox:1.37`).

## Hints

- A headless Service is a normal Service with `clusterIP: None`. `clusterIP` cannot be changed on an existing Service, so set it at creation.
- `kubectl create service clusterip <name> --clusterip=None --tcp=9200:9200` and `kubectl create service externalname <name> --external-name=<fqdn>` exist. A Service created this way selects `app=<service name>`, so check the selector.
- The FQDN of the target is `postgres.datastore.svc.cluster.local`. For `search-headless`, set `spec.selector` to `app: search`.

## Solution

```yaml
apiVersion: v1
kind: Service
metadata:
  name: search-headless
  namespace: lookup
spec:
  clusterIP: None
  selector:
    app: search
  ports:
  - port: 9200
    targetPort: 9200
---
apiVersion: v1
kind: Service
metadata:
  name: {{EXT_NAME}}
  namespace: lookup
spec:
  type: ExternalName
  externalName: postgres.datastore.svc.cluster.local
```

```bash
k config use-context {{CONTEXT}}
k apply -f services.yaml
k -n lookup run dnstest --rm -it --image=busybox:1.37 --restart=Never -- sh -c \
  'nslookup search-headless.lookup.svc.cluster.local; nslookup {{EXT_NAME}}.lookup.svc.cluster.local'
```

The headless Service gets no ClusterIP and no kube-proxy rules: CoreDNS answers with one A record per ready pod, which is what StatefulSets and client-side load balancing rely on. An ExternalName Service has no selector and no endpoints. CoreDNS answers with a CNAME to `externalName`, and the client resolves that name in turn. `kubectl create service clusterip search-headless --clusterip=None` would set the selector to `app=search-headless` and match no pods.
