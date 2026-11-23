# Exercise 24 — PriorityClass and Patch Operations

> Related: [PriorityClass skeleton](../../skeletons/priorityclass.yaml) | [README — Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Create a high-priority pod that gets scheduled before lower-priority pods. Practice using `kubectl patch` to modify existing resources without editing manifests.

## Tasks

1. Create a namespace called `exercise-24`
2. Create a PriorityClass with:
   - Name: `high-priority`
   - Value: `999999999` (one less than 1000000000 — max priority)
   - Description: "Critical workload"
3. Create a Deployment named `critical-app`:
   - 1 replica initially
   - Image: `busybox:1.36`
   - Do NOT specify priorityClassName yet
4. Use `kubectl patch` to add `priorityClassName: high-priority` to the Deployment
5. Verify the pod has the priority class assigned
6. Create a second lower-priority Deployment to compare
7. Verify scheduling order respects priority

## Key Learning

- PriorityClass affects pod scheduling order
- Higher value = higher priority = schedules first
- `kubectl patch` is faster than editing files in exam
- Exam often asks: "Update this Deployment using only kubectl" → patch is the answer

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k create priorityclass high-priority --value=999999`
- `k patch deployment <name> -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'`
- Verify patch worked: `k get deploy <name> -o jsonpath='{.spec.template.spec.priorityClassName}'`
- Check pod has priority: `k get pod <pod> -o jsonpath='{.spec.priorityClassName}'`

</details>

## What tripped me up

> I created the PriorityClass but forgot you need to set it on the Pod template spec, not the Deployment spec. The patch syntax is tricky. I also initially tried to edit the YAML file instead of using patch, which wastes time on the exam. The correct approach: create PriorityClass first, then patch the Deployment's pod template to add it.
>
> Also: I used a lower value (100) when the exam said "high priority." The scale is: system-cluster-critical (2000000000), system-node-critical (2000001000), user values usually 0-1000000000. Going close to max (999999999) ensures your pod gets scheduled first even under resource pressure.

## Verify

```bash
# PriorityClass exists
k get priorityclass high-priority

# Deployment has correctValue
k get deploy critical-app -n exercise-24 -o jsonpath='{.spec.template.spec.priorityClassName}'

# Pod has the priority class
k get pod -n exercise-24 -o jsonpath='{.items[0].spec.priorityClassName}'

# Check priority value
k describe priorityclass high-priority
```

## Cleanup

```bash
k delete ns exercise-24
k delete priorityclass high-priority
```

<details>
<summary>Solution</summary>

```bash
k create ns exercise-24
kn exercise-24

# Create PriorityClass
k create priorityclass high-priority --value=999999999 --description="Critical workload"

# Verify it was created
k get priorityclass high-priority

# Create deployment WITHOUT priorityClassName
k create deployment critical-app --image=busybox:1.36 --replicas=1 $do > deploy.yaml
# (image is sleep 3600 in original, but busybox defaults are fine)

k apply -f deploy.yaml

# Now patch the deployment to add priorityClassName
# Target: spec.template.spec.priorityClassName
k patch deployment critical-app -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'

# Verify patch was applied
k get deploy critical-app -o jsonpath='{.spec.template.spec.priorityClassName}'
# Output: high-priority

# The pod will be recreated with the new priority class
k get pods -n exercise-24

# Verify pod has it
k get pod -n exercise-24 -o jsonpath='{.items[0].spec.priorityClassName}'
# Output: high-priority

# Check priority value
k get priorityclass high-priority -o jsonpath='{.value}'
# Output: 999999999

# Cleanup
k delete ns exercise-24
k delete priorityclass high-priority
```

Alternative patch with explicit field path (if JSON patch fails):

```bash
k patch deployment critical-app --type='json' -p='[{"op": "add", "path": "/spec/template/spec/priorityClassName", "value":"high-priority"}]'
```

</details>
