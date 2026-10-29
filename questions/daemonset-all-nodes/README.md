# DaemonSet on all nodes

**Context:** `kubectl config use-context {{CONTEXT}}`

Create a DaemonSet named `node-agent` in namespace `node-agents`:

- pod label `app=node-agent`
- container `agent`, image `busybox:1.37`, command `sleep 86400`
- resource requests `10m` CPU and `16Mi` memory
- one pod on every node of the cluster, including the control plane node

## Hints

- There is no `kubectl create daemonset`: generate a Deployment with `$do`, change the kind and remove replicas/strategy.
- The control plane node has a NoSchedule taint. Which toleration lets pods in anyway?
- Compare DESIRED in `kubectl get ds` with the number of nodes.

## Solution

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: node-agents
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: busybox:1.37
        command: ["sleep", "86400"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
```

There is no `kubectl create daemonset`. Generate a Deployment with `$do`, then change `kind`, and remove `replicas` and `strategy`. Without the toleration you get 2 of 3 pods. The control plane's `NoSchedule` taint keeps the third one away.
