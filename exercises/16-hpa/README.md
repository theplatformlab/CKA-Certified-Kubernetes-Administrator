# Exercise 16 — Horizontal Pod Autoscaler

> **Medium** | ~15 min | Domain: Workloads & Scheduling (15%)
>
> Related: [HPA skeleton](../../skeletons/hpa.yaml) | [README — Workloads & Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Configure a Horizontal Pod Autoscaler to scale a deployment based on CPU usage. Also understand Vertical Pod Autoscaler for resource optimization. This requires the metrics-server to be installed in the cluster.

## Context: HPA vs VPA

HPA (Horizontal Pod Autoscaler) scales the number of replicas based on metrics like CPU or memory. When CPU exceeds target, HPA creates more pods. When load drops, it removes pods.

VPA (Vertical Pod Autoscaler) adjusts the CPU and memory requests/limits for existing pods based on actual usage. If a pod requests 256Mi memory but only uses 64Mi, VPA recommends lowering the request. This doesn't scale replicas; it optimizes resource allocation to improve bin-packing and reduce waste.

The CKA focuses on HPA, but understanding VPA helps with cluster resource efficiency.

## Tasks (HPA)

Work in namespace `exercise-16` (`./scripts/lab.sh setup 16` creates it and installs metrics-server). metrics-server v0.9.0 runs in the cluster with `--kubelet-insecure-tls`, because kind's kubelet serving certificates are self-signed.

1. Verify the metrics-server is running in the cluster (`k top nodes` returns data)
2. Create a Deployment named `load-app` with:
   - Image: `nginx:1.27`, container port 80, pod label `app=load-app`
   - 1 replica
   - CPU request: 50m
   - CPU limit: 100m
3. Expose it with a ClusterIP Service named `load-svc` on port 80
4. Create an HPA named `load-app` targeting the Deployment `load-app`:
   - Min replicas: 1
   - Max replicas: 5
   - **Target CPU utilization: 50%** (must be specified as `type: Utilization` with `averageUtilization: 50`)
5. Verify the HPA YAML has correct structure (target type is `Utilization`, not `AverageValue`)
6. Generate load against the service and observe the HPA scaling up (a single `wget` loop pushes nginx above 50% of its 50m request)
7. Stop the load and observe the HPA scaling back down

Validate with `./scripts/lab.sh check 16` (it also checks that the HPA reads a current CPU value and has scaled at least once).

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k top pods -n exercise-16` to check if metrics-server is working
- `k autoscale deployment load-app --cpu=50% --min=1 --max=5` creates a basic HPA (`--cpu-percent` is deprecated in kubectl 1.35)
- **Verify HPA structure:** After creating the HPA, run `k get hpa -n exercise-16 -o yaml` and check that:
  - `spec.metrics[0].type` == `Resource`
  - `spec.metrics[0].resource.target.type` == `Utilization` (not `AverageValue`)
  - `spec.metrics[0].resource.target.averageUtilization` == 50
- Load generation: `k run load-gen -n exercise-16 --image=busybox:1.36 --rm -it --restart=Never -- sh -c "while true; do wget -q -O- http://load-svc.exercise-16 >/dev/null; done"`
- Scale down takes a few minutes after load stops (by design, to avoid flapping)

**HPA Pre-Flight Checklist (Reddit: This solves 80% of HPA issues)**
```bash
# 1. Is metrics-server running?
k get deployment -n kube-system metrics-server
# If not running: missing from the cluster; ./scripts/lab.sh setup 16 installs it

# 2. Does `kubectl top` work?
k top nodes
k top pods -n exercise-16
# If "metrics not available": wait 60 seconds (metrics collection delay)

# 3. Does Deployment have resource requests?
k get deployment load-app -n exercise-16 -o json | jq '.spec.template.spec.containers[0].resources'
# Must show: "requests": {"cpu": "50m"} (or similar value)
# If empty {}: **This is why HPA shows <unknown>**, add requests to deployment

# 4. Is HPA watching the right target.type?
k get hpa -n exercise-16 -o yaml | grep -A5 "metrics:"
# Must show: type: Utilization (NOT AverageValue or cpu)
# If wrong: recreate HPA with: k autoscale deployment load-app --cpu=50%

# 5. Is HPA showing valid metrics?
k get hpa -n exercise-16
# Should show: TARGETS "X%/50%" or "100m/50m"
# If "unknown/50%": problem is Deployment has no resource.requests
```

**Target Type vs. Target Value (Commonly Confused)**
- `type: Utilization` + `averageUtilization: 50` = Scale when 50% of *requested* CPU in use
  - Example: Pod requests 100m CPU, use 50m → 50% = scale trigger
  - **This is what most exams test**
- `type: Value` + `averageValue: 50m` = Scale when average pod uses exactly 50m CPU
  - Less common; requires knowing absolute metrics in advance
- **Exam gotcha:** Using `type: Value` when question implies `Utilization` → HPA never scales

</details>

## What tripped me up

> **Missing Resource Requests = Unknown Metrics (Reddit #1 HPA Complaint)**
>
> HPA showed `<unknown>/50%` for CPU and never scaled. I stared at the HPA for 5 minutes thinking the metrics-server was broken. The actual problem: my Deployment didn't have `resources.requests.cpu` set. HPA calculates percentage based on *requested* CPU. No request = no baseline = `<unknown>`. **Always set resource requests on pods that need autoscaling.** See pre-flight checklist above.

> **Target Type Must Be Utilization, Not AverageValue (Reddit #2 HPA Bug)**
>
> Created an HPA and it compiled, but `k get hpa` showed `<unknown>` metrics. When I checked the YAML with `k get hpa -o yaml`, I saw `target.type: AverageValue` instead of `target.type: Utilization`. The metrics-server can't compute AverageValue for CPU (that's for custom metrics). For CPU, must use type: `Utilization`. Check the imperative command's generated YAML carefully.

> **Scale-Down is Deliberately Slow**
>
> After I stopped generating load, replicas stayed high for 5 minutes. I thought the HPA was broken and kept restarting things. It's not broken—it's conservative. By default, HPA waits 5 minutes after load drops before scaling down (to avoid flapping). Don't panic if replicas stay high briefly after stopping load.

> **Metrics-Server Isn't Always Installed**
>
> `k top pods` returned an error. Metrics-server wasn't installed on the cluster. HPA cannot function without metrics-server (or equivalent metrics provider). On managed clusters (EKS, GKE, AKS), it's usually pre-installed. On kubeadm clusters, you have to install it manually: `k apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`

## Verify

```bash
./scripts/lab.sh check 16
```

Manual checks:

```bash
# HPA created
k get hpa -n exercise-16

# Under load: replicas should increase
k get hpa -n exercise-16 -w

# Pods scaling
k get pods -n exercise-16 -w
```

## Cleanup

```bash
./scripts/lab.sh cleanup 16     # also removes metrics-server if setup installed it
```

<details>
<summary>Solution</summary>

```bash
# Check metrics-server (installed by ./scripts/lab.sh setup 16)
k get pods -n kube-system | grep metrics-server
k top nodes   # should return data
```

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-app
  namespace: exercise-16
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-app
  template:
    metadata:
      labels:
        app: load-app
    spec:
      containers:
      - name: app
        image: nginx:1.27
        resources:
          requests:
            cpu: "50m"
          limits:
            cpu: "100m"
        ports:
        - containerPort: 80
```

```bash
k apply -f deployment.yaml

# Create service
k expose deployment load-app -n exercise-16 --port=80 --target-port=80 --name=load-svc

# Option 1: Create HPA imperatively
k autoscale deployment load-app -n exercise-16 --cpu=50% --min=1 --max=5

# Option 2: Create HPA declaratively (to verify structure)
k apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: load-app
  namespace: exercise-16
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: load-app
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

# Verify HPA structure
k get hpa -n exercise-16 -o yaml
# Check: metrics[0].resource.target.type should be "Utilization"
# Check: metrics[0].resource.target.averageUtilization should be 50

# Generate load (run in a separate terminal)
k run load-gen -n exercise-16 --image=busybox:1.36 --rm -it --restart=Never -- sh -c \
  "while true; do wget -q -O- http://load-svc.exercise-16 >/dev/null; done"

# Watch scaling in another terminal (TARGETS climbs above 50%, REPLICAS goes up within ~1-2 min)
k get hpa -n exercise-16 -w
k get pods -n exercise-16 -w

# Stop load (Ctrl+C on the load-gen terminal)
# Wait a few minutes for scale-down
```

</details>

## Optional: Vertical Pod Autoscaler (VPA) Understanding

While VPA is not always tested on the CKA, understanding it helps optimize workloads and appears in cluster efficiency questions. VPA recommends resource adjustments but doesn't enforce them automatically—you review recommendations and apply them.

VPA workflow:

```bash
# Install VPA (if not already installed)
# VPA components: Recommender, Updater, Admission Controller
# Usually installed via: git clone https://github.com/kubernetes/autoscaler.git
# ./autoscaler/vertical-pod-autoscaler/hack/vpa-up.sh

# After VPA is running, create a VPA policy
kubectl apply -f - <<EOF
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: vpa-example
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: load-app
  updatePolicy:
    updateMode: "Off"  # "Off" = recommendations only, no changes
EOF

# Check VPA recommendations (after metrics are collected)
k get vpa vpa-example --watch
k describe vpa vpa-example

# View recommended resource changes
k get vpa vpa-example -o jsonpath='{.status.recommendation}'
```

Key VPA concepts:

- updateMode: "Off" (recommendations only), "Initial" (apply on pod creation), "Recreate" (apply and restart pods), "Auto" (smart choice)
- VPA may recreate pods to apply new resource requests—plan for disruption
- VPA works best with PodDisruptionBudgets to avoid cascading disruptions
- Unlike HPA, VPA requires the Recommender to collect metrics first (takes 1-5 minutes)
