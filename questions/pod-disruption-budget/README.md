# PodDisruptionBudget

**Context:** `kubectl config use-context {{CONTEXT}}`

Deployment `frontend` in namespace `web` runs {{REPLICAS}} replicas with pod label `app=frontend`.

Create a PodDisruptionBudget named `frontend-pdb` in namespace `web` that allows at most `{{MAX_UNAVAILABLE}}` of these pods to be unavailable during voluntary disruptions.

## Hints

- `kubectl create pdb <name> --selector=... --max-unavailable=...`
- ALLOWED DISRUPTIONS in `kubectl get pdb` only shows the expected value once all pods are ready.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n web create pdb frontend-pdb --selector=app=frontend --max-unavailable={{MAX_UNAVAILABLE}}
k -n web get pdb frontend-pdb       # ALLOWED DISRUPTIONS {{MAX_UNAVAILABLE}}
```

`--min-available` with the matching number would behave the same for this replica count, but the question asks for `maxUnavailable`, so the grader checks that field. Try it: `k drain <worker> --ignore-daemonsets` now evicts at most 2 frontend pods at a time and waits for replacements.
