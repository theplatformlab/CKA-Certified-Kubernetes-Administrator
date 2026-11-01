# Allow only trusted image registries

**Context:** `kubectl config use-context {{CONTEXT}}`

Pods in namespace `retail-prod` may only run images from the company's registries: `registry.k8s.io` and `{{REGISTRY}}`. Enforce this with the built-in admission control, no webhook:

1. Create a ValidatingAdmissionPolicy `allowed-registries` that rejects the creation and update of Pods if any container or init container uses an image that does not come from `registry.k8s.io` or `{{REGISTRY}}`. An image like `nginx:1.28` (Docker Hub) must be rejected.
2. Create a ValidatingAdmissionPolicyBinding `allowed-registries-binding` that enforces the policy (requests are denied) in namespace `retail-prod` only.
3. Test it: try to create a pod `nginx-test` with image `nginx:1.28` in `retail-prod` and save the error message to `{{WORKDIR}}/rejected.txt`.

## Hints

- The kubernetes.io page "Validating Admission Policy" has a full example. The policy holds `matchConstraints` (which requests) and CEL `validations`; the binding names the policy, its `validationActions` (`[Deny]`) and `matchResources` (a `namespaceSelector` on the label `kubernetes.io/metadata.name`).
- `object.spec.containers.all(c, <condition on c.image>)` checks every container. `initContainers` is optional in a Pod: guard it with `!has(object.spec.initContainers) || ...`.
- Compare with the trailing slash: `c.image.startsWith('registry.k8s.io/')`. Without it, `registry.k8s.io.evil.example/...` would pass. Test without creating anything: `k apply --dry-run=server -f pod.yaml`.

## Solution

```bash
k config use-context {{CONTEXT}}
```

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: allowed-registries
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  variables:
  - name: images
    expression: >-
      object.spec.containers.map(c, c.image) +
      (has(object.spec.initContainers) ? object.spec.initContainers.map(c, c.image) : [])
  validations:
  - expression: >-
      variables.images.all(i, i.startsWith('registry.k8s.io/') || i.startsWith('{{REGISTRY}}/'))
    message: "images must come from registry.k8s.io or {{REGISTRY}}"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: allowed-registries-binding
spec:
  policyName: allowed-registries
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: retail-prod
```

```bash
k apply -f allowed-registries.yaml
k -n retail-prod run nginx-test --image=nginx:1.28 2> {{WORKDIR}}/rejected.txt
cat {{WORKDIR}}/rejected.txt
# The pods "nginx-test" is invalid: : ValidatingAdmissionPolicy 'allowed-registries' with binding
# 'allowed-registries-binding' denied request: images must come from registry.k8s.io or {{REGISTRY}}
k -n retail-prod run pause-test --image=registry.k8s.io/pause:3.10 --dry-run=server   # allowed
```

The policy alone does nothing: only a binding makes it act, and its `validationActions` decide how (`Deny`, or just `Warn`/`Audit`). Without the `namespaceSelector` the binding would apply to every namespace, including `kube-system`. A short name like `nginx:1.28` is really `docker.io/library/nginx:1.28`, but the policy only sees the string in the pod spec, so a prefix check rejects it either way. The check matches Pods, so a Deployment with a forbidden image is still created, but its ReplicaSet can't create pods (`k describe rs` shows the denial). Ephemeral containers (`kubectl debug`) go through the `pods/ephemeralcontainers` subresource and would need their own rule.
