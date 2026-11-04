# Node affinity and topology spread

**Context:** `kubectl config use-context {{CONTEXT}}`

The worker nodes of the cluster carry the label `node-pool={{POOL}}`.

Create a Deployment named `edge-proxy` in namespace `edge`:

1. Image `nginx:1.28`, `{{REPLICAS}}` replicas, pod label `app=edge-proxy`.
2. The pods may only be scheduled on nodes with the label `node-pool={{POOL}}`. Use a **required** node affinity rule with the `In` operator.
3. The pods must be spread evenly across the nodes: a topology spread constraint with `maxSkew: 1` over `kubernetes.io/hostname` that refuses to schedule a pod which would violate it. It must select the pods by `app=edge-proxy`.

## Hints

- `k get nodes -L node-pool` shows the labels. `k explain deploy.spec.template.spec.affinity.nodeAffinity` and `k explain deploy.spec.template.spec.topologySpreadConstraints`.
- Node affinity: `requiredDuringSchedulingIgnoredDuringExecution` -> `nodeSelectorTerms` -> `matchExpressions`.
- The spread constraint needs `maxSkew`, `topologyKey`, `whenUnsatisfiable: DoNotSchedule` and a `labelSelector`.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n edge create deployment edge-proxy --image=nginx:1.28 --replicas={{REPLICAS}} $do > edge.yaml
```

```yaml
# edge.yaml, under spec.template.spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-pool
                operator: In
                values: [{{POOL}}]
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: edge-proxy
      containers:
      - name: nginx
        image: nginx:1.28
```

```bash
k apply -f edge.yaml
k -n edge get pods -o wide        # {{REPLICAS}} pods, half on each worker
```

By default the spread constraint only counts nodes that pass the pod's node affinity (`nodeAffinityPolicy: Honor`). The control plane doesn't carry the label, so it isn't a domain with 0 pods that would block scheduling. `whenUnsatisfiable: ScheduleAnyway` would only be a soft preference.
