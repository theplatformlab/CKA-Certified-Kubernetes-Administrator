# Protect the cloud metadata endpoint

**Context:** `kubectl config use-context {{CONTEXT}}`

The nodes of cluster `{{CLUSTER}}` run on cloud VMs. Every pod can query the instance metadata service at `169.254.169.254`, which hands out the node's identity and cloud credentials. Try it: `k -n fleet-sync exec deploy/sync-api -- wget -qO- http://169.254.169.254/latest/meta-data/iam/security-credentials/node-instance-role`.

In namespace `fleet-sync`:

1. Create a NetworkPolicy `deny-cloud-metadata` that applies to **all** pods of the namespace and blocks outgoing traffic to `169.254.169.254`, while all other outgoing traffic (DNS, other pods, the API server, the internet) keeps working. Do not restrict incoming traffic.
2. The pods of Deployment `node-inventory` (label `app=node-inventory`) need the metadata service. Create a second NetworkPolicy `allow-cloud-metadata` that allows them to reach `169.254.169.254`.

## Hints

- An `ipBlock` with `cidr: 0.0.0.0/0` and an `except` list allows every IPv4 destination except the ones you list.
- Once a pod is selected by a policy with `policyTypes: [Egress]`, only what its policies allow gets out. List only `Egress` in `policyTypes`, otherwise you isolate incoming traffic too.
- Policies add up: a second policy that selects `app=node-inventory` and allows `169.254.169.254/32` opens that destination again for those pods only.

## Solution

```bash
k config use-context {{CONTEXT}}
```

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cloud-metadata
  namespace: fleet-sync
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-cloud-metadata
  namespace: fleet-sync
spec:
  podSelector:
    matchLabels:
      app: node-inventory
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 169.254.169.254/32
```

```bash
k apply -f metadata-policies.yaml
k -n fleet-sync exec deploy/sync-api -- wget -qO- -T 3 http://169.254.169.254/latest/meta-data/instance-id        # times out
k -n fleet-sync exec deploy/node-inventory -- wget -qO- -T 3 http://169.254.169.254/latest/meta-data/instance-id  # i-0f3a...
k -n fleet-sync exec deploy/sync-api -- nslookup kubernetes.default                                                  # DNS still works
```

There is no way to say "deny X" in a NetworkPolicy, only "allow everything except X": the `except` list of an `ipBlock` does that. The `0.0.0.0/0` block also covers pod IPs and the cluster DNS, so nothing else breaks. `node-inventory` is selected by both policies; its allowed egress is the union of the two, so it reaches the metadata service again. In a real cluster the metadata service is not a Kubernetes object at all, so blocking it at the network level (or with the cloud provider's metadata protection, e.g. IMDSv2 hop limit) is the only way.
