# Egress NetworkPolicy with DNS

**Context:** `kubectl config use-context {{CONTEXT}}`

Namespace `ledger-app` has a NetworkPolicy `default-deny-egress` that blocks all outgoing traffic. Since it was added, the pods of Deployment `api` (label `app=api`) cannot even resolve names. They need to send HTTP requests to the Service `audit` in namespace `audit-log` (`http://audit.audit-log`, Service port `80`).

Create a NetworkPolicy named `api-egress` in namespace `ledger-app` so that pods with label `app=api`:

1. can resolve DNS names using the cluster DNS (CoreDNS pods with label `k8s-app=kube-dns` in namespace `kube-system`, UDP and TCP port `53`),
2. can connect to the pods behind Service `audit` in namespace `audit-log`,
3. cannot open any other outgoing connection (for example to Service `metrics` in `audit-log`).

Do not modify or delete `default-deny-egress`. Other pods in `ledger-app` must stay fully isolated.

## Hints

- NetworkPolicies are additive: a second policy that selects `app=api` and allows some egress opens exactly that, while `default-deny-egress` keeps blocking the rest.
- To select pods in another namespace, combine a `namespaceSelector` (`kubernetes.io/metadata.name: kube-system`) and a `podSelector` in the same `to` entry.
- Policies are evaluated against pod IPs and container ports, not the Service port: check the `targetPort` of Service `audit` (`k -n audit-log get svc audit -o yaml`), which is `{{AUDIT_PORT}}`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n audit-log get svc audit -o jsonpath='{.spec.selector} {.spec.ports[0].targetPort}'   # {"app":"audit"} {{AUDIT_PORT}}
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
  namespace: ledger-app
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: audit-log
      podSelector:
        matchLabels:
          app: audit
    ports:
    - protocol: TCP
      port: {{AUDIT_PORT}}
```

```bash
k -n ledger-app exec deploy/api -- wget -qO- -T 3 http://audit.audit-log
```

Two traps: the policy sees traffic after the Service has been translated to a pod IP, so the port is the container port `{{AUDIT_PORT}}`, not the Service port `80`. And `namespaceSelector` and `podSelector` must be in the **same** list item (no `-` before `podSelector`); as two items they would allow all pods in `kube-system` or every `app=audit` pod in `ledger-app`. Without the DNS rule, `wget http://audit.audit-log` fails already at name resolution.
