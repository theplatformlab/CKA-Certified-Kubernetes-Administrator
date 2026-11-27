# Exercise 34 — CRD Discovery and kubectl explain

> **Medium** | ~15 min | Domain: Cluster Architecture (25%)
>
> Related: [Kubernetes CRD documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) | [Exercise 31 — Argo CD](../31-argocd-gitops-setup/)

A custom resource definition (CRD) is installed by an operator. Use the Kubernetes API to discover the CRD, inspect its served API version and schema, create a custom resource, and read a field through `kubectl explain`.

## Lab Requirements

- Cluster: single-node kind or Minikube
- Components: none beyond Kubernetes API discovery
- Access: permission to create CRDs, list CRDs, and create custom resources
- Test record: Not tested

## Setup

Create a small CRD and one custom resource:

```bash
k apply -f - <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.platform.example
spec:
  group: platform.example
  scope: Namespaced
  names:
    plural: databases
    singular: database
    kind: Database
    shortNames:
    - db
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              engine:
                type: string
              replicas:
                type: integer
              storage:
                type: string
EOF

k create namespace exercise-34
```

## Tasks

1. Find the CRD named `databases.platform.example`.
2. Confirm its group, scope, served version, resource name, and short name.
3. Use `kubectl api-resources` to confirm the resource is visible.
4. Use `kubectl explain` to inspect:
   - `Database`
   - `Database.spec`
   - `Database.spec.engine`
5. Create a Database custom resource named `main-db` in `exercise-34`:
   - `engine: postgres`
   - `replicas: 2`
   - `storage: 10Gi`
6. Verify the resource through the CRD API and delete it.

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- CRD names end with the group, for example `databases.platform.example`.
- Use `k get crd databases.platform.example -o yaml` for schema details.
- `k api-resources --api-group=platform.example` lists custom resources.
- `k explain database --api-version=platform.example/v1` sets the API version explicitly.

</details>

## Verify

```bash
k get crd databases.platform.example
k get crd databases.platform.example \
  -o jsonpath='{.spec.group}{"/"}{.spec.versions[?(@.served==true)].name}{" "}{.spec.scope}{"\n"}'
k api-resources --api-group=platform.example
k explain database --api-version=platform.example/v1
k explain database.spec --api-version=platform.example/v1
k explain database.spec.engine --api-version=platform.example/v1
k get database main-db -n exercise-34 -o yaml
```

## Cleanup

```bash
k delete namespace exercise-34
k delete crd databases.platform.example
```

<details>
<summary>Solution</summary>

Create the custom resource:

```yaml
apiVersion: platform.example/v1
kind: Database
metadata:
  name: main-db
  namespace: exercise-34
spec:
  engine: postgres
  replicas: 2
  storage: 10Gi
```

Apply and verify:

```bash
k apply -f database.yaml
k get databases -n exercise-34
k get db main-db -n exercise-34 -o yaml
k explain database.spec.replicas --api-version=platform.example/v1
k delete database main-db -n exercise-34
```

The CRD's OpenAPI schema makes `kubectl explain` work. The CRD can validate fields that exist in the schema, but this setup should be used only to test discovery and field structure.

</details>
