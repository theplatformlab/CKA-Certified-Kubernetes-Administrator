# Exercise 24 — PriorityClass and Patch Operations

> Related: [PriorityClass skeleton](../../skeletons/priorityclass.yaml) | [README — Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Create a high-priority pod that gets scheduled before lower-priority pods. Practice using `kubectl patch` to modify existing resources without editing manifests.

## Tasks

Work in namespace `exercise-24` (`./scripts/lab.sh setup 24` creates it).

1. Create a PriorityClass with:
   - Name: `high-priority`
   - Value: `999999` (user-defined classes may go up to 1,000,000,000; higher values are reserved for `system-*` classes)
   - Description: `Critical workload`
   - not the global default
2. Create a Deployment named `critical-app`:
   - 1 replica
   - Image: `busybox:1.36`, command `sleep 3600` (busybox exits immediately without a command)
   - Do NOT specify priorityClassName yet
3. Use `kubectl patch` to add `priorityClassName: high-priority` to the Deployment's pod template
4. Verify the new pod has the priority class and priority `999999` assigned
5. Create a PriorityClass `low-priority` with value `1000` and a second Deployment `background-app` (1 replica, `busybox:1.36`, command `sleep 3600`) that uses it
6. Compare the `spec.priority` of both pods — under resource pressure the scheduler places (and preempts in favour of) the higher value first

Validate with `./scripts/lab.sh check 24` (it also checks that `critical-app` was changed after creation: rollout revision 2 or higher).

## Key Learning

- PriorityClass affects pod scheduling order
- Higher value = higher priority = schedules first
- `kubectl patch` is faster than editing files in exam
- Exam often asks: "Update this Deployment using only kubectl" → patch is the answer

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- `k create priorityclass high-priority --value=999999 --description="Critical workload"`
- `k create deployment <name> --image=busybox:1.36 -- sleep 3600` sets the command
- `k patch deployment <name> -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'`
- Verify patch worked: `k get deploy <name> -o jsonpath='{.spec.template.spec.priorityClassName}'`
- Check pod has priority: `k get pod <pod> -o jsonpath='{.spec.priorityClassName}'`

</details>

## What tripped me up

> I created the PriorityClass but forgot you need to set it on the Pod template spec, not the Deployment spec. The patch syntax is tricky. I also initially tried to edit the YAML file instead of using patch, which wastes time on the exam. The correct approach: create PriorityClass first, then patch the Deployment's pod template to add it.
>
> Also: I used a lower value (100) when the exam said "high priority." The scale is: system-cluster-critical (2000000000), system-node-critical (2000001000), user values usually 0-1000000. Going close to max (999999) ensures your pod gets scheduled first even under resource pressure.

## Verify

```bash
./scripts/lab.sh check 24
```

Manual checks:

```bash
# PriorityClass exists
k get priorityclass high-priority

# Deployment has the correct value
k get deploy critical-app -n exercise-24 -o jsonpath='{.spec.template.spec.priorityClassName}'

# Pods have the priority class and the resolved priority
k get pods -n exercise-24 -o custom-columns=NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIORITY:.spec.priority

# Check priority value
k describe priorityclass high-priority
```

## Cleanup

```bash
./scripts/lab.sh cleanup 24     # namespace and both PriorityClasses
```

<details>
<summary>Solution</summary>

```bash
kn exercise-24

# Create PriorityClass
k create priorityclass high-priority --value=999999 --description="Critical workload"

# Verify it was created
k get priorityclass high-priority

# Create deployment WITHOUT priorityClassName (busybox needs a command to keep running)
k create deployment critical-app --image=busybox:1.36 --replicas=1 -- sleep 3600

# Now patch the deployment to add priorityClassName
# Target: spec.template.spec.priorityClassName
k patch deployment critical-app -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'

# Verify patch was applied
k get deploy critical-app -o jsonpath='{.spec.template.spec.priorityClassName}'
# Output: high-priority

# The pod is recreated with the new priority class (rollout revision 2)
k rollout status deployment critical-app
k get pods -l app=critical-app -o jsonpath='{.items[0].spec.priorityClassName} {.items[0].spec.priority}'
# Output: high-priority 999999

# Lower-priority deployment to compare
k create priorityclass low-priority --value=1000 --description="Background workload"
k create deployment background-app --image=busybox:1.36 -- sleep 3600
k patch deployment background-app -p '{"spec":{"template":{"spec":{"priorityClassName":"low-priority"}}}}'

k get pods -o custom-columns=NAME:.metadata.name,CLASS:.spec.priorityClassName,PRIORITY:.spec.priority
```

Alternative patch with explicit field path (if JSON patch fails):

```bash
k patch deployment critical-app --type='json' -p='[{"op": "add", "path": "/spec/template/spec/priorityClassName", "value":"high-priority"}]'
```

</details>
