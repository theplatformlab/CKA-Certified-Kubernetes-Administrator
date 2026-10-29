# Exercise 10 — Static Pod

> Related: [Pod skeleton](../../skeletons/pod.yaml) | [README — Workloads & Scheduling](../../README.md#domain-3--workloads--scheduling-15)

Create a static pod by placing a manifest in the kubelet's static pod directory. Static pods are managed directly by the kubelet, not the API server.

## Tasks

Work in namespace `exercise-10` (`./scripts/lab.sh setup 10` creates it) on the ops cluster (`./scripts/init-cluster.sh --profile ops`). The static pod runs on the worker node `cka-ops-worker`. Open a shell on it with `docker exec -it cka-ops-worker bash` — the kind equivalent of `ssh cka-ops-worker` in the exam.

1. On `cka-ops-worker`, find the static pod manifest directory in the kubelet config
2. Create the manifest `static-web.yaml` in that directory for a pod named `static-web` in namespace `exercise-10`:
   - label `app=static-web`
   - one container named `web`, image `nginx:1.27`, containerPort `80`
3. Verify the static pod appears in `k get pods -n exercise-10` as `static-web-cka-ops-worker` (the node name is appended) and is Running
4. Try to delete the pod with `kubectl` — observe that it comes back
5. Leave the static pod running and validate with `./scripts/lab.sh check 10`

Removing the manifest (the only way to really delete a static pod) is part of [Cleanup](#cleanup).

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- The static pod path is configured in the kubelet config, usually `/etc/kubernetes/manifests/`
- Check kubelet config: `cat /var/lib/kubelet/config.yaml | grep staticPodPath`
- Static pods show up in `kubectl` but can't be deleted through the API — the kubelet recreates them
- The pod name will be `static-web-<node-name>`
- Put `namespace: exercise-10` in the manifest's metadata — without it the pod lands in `default`; the mirror pod only shows up if the namespace exists

</details>

## Verify

```bash
./scripts/lab.sh check 10
```

Manual checks:

```bash
# Should show static-web-cka-ops-worker
k get pods -n exercise-10 -o wide

# ownerReferences point to the Node: this is the read-only mirror of a static pod
k get pod static-web-cka-ops-worker -n exercise-10 -o jsonpath='{.metadata.ownerReferences[0].kind}{"\n"}'
```

## Cleanup

Delete the static pod the only way that works — remove the manifest on the node — and watch it disappear:

```bash
docker exec cka-ops-worker rm /etc/kubernetes/manifests/static-web.yaml
k get pods -n exercise-10        # gone after a few seconds
./scripts/lab.sh cleanup 10      # removes the manifest (if still there) and the namespace
```

## What tripped me up

> **Static Pods Can't Be Deleted Via kubectl**
>
> I kept running `kubectl delete pod static-web-node01` and it kept coming back 5 seconds later. I did this four times before I realized: kubelet manages static pods, not the API server. You CANNOT delete a static pod through kubectl — you have to SSH into the node and delete the manifest file from `/etc/kubernetes/manifests/`. The kubelet immediately recreates any missing static pods. This is one of those things that feels wrong but is correct by design.

> **Verify the Actual staticPodPath**
>
> Forgot to check the actual path on the node. Placed the manifest in the "usual" spot, but the kubelet was configured to look elsewhere. Always verify: `cat /var/lib/kubelet/config.yaml | grep staticPodPath`. Paths are configurable and exam clusters might differ from defaults. A typo in the path means the pod never appears.

> **Kubelet Config Comments Can Hide Issues**
>
> Added a commented-out flag in the kubelet config as a reminder: `# --feature-gates=...`. Later, when examining the kubelet configuration to debug a static pod issue, I couldn't find the real value because my commented version was at the top of the file. When analyzing kubelet flags or troubleshooting, strip comments to see the actual active configuration: `grep -v "^[[:space:]]*#" /var/lib/kubelet/config.yaml`. Comments matter for reading clarity but not for what kubelet executes.

> **Static Pod Names Include Node Name**
>
> Created a static pod named `static-web` and couldn't find it with `k get pods static-web`. Turns out the system appends the node name: if the node is `control-plane`, the pod is `static-web-control-plane`. Always search by pattern: `k get pods -A | grep static-web`.

> **kubelet Needs Time to Pick Up Manifests**
>
> Placed the manifest and immediately ran `kubectl get pods` — pod wasn't there. Thought it was broken. Actually waited 2-3 seconds and kubelet detected it. Don't panic if the static pod isn't immediate. Give the kubelet time to scan `/etc/kubernetes/manifests/` (default scan interval is a few seconds).

<details>
<summary>Solution</summary>

```bash
# Open a shell on the worker node (exam: ssh cka-ops-worker)
docker exec -it cka-ops-worker bash

# Step 1: Find static pod path
grep staticPodPath /var/lib/kubelet/config.yaml
# staticPodPath: /etc/kubernetes/manifests

# Step 2: Create the manifest
tee /etc/kubernetes/manifests/static-web.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: static-web
  namespace: exercise-10
  labels:
    app: static-web
spec:
  containers:
  - name: web
    image: nginx:1.27
    ports:
    - containerPort: 80
EOF
exit

# Step 3: Verify (wait a few seconds for kubelet to pick it up)
k get pods -n exercise-10
# static-web-cka-ops-worker   1/1   Running

# Step 4: Try to delete via kubectl
k delete pod static-web-cka-ops-worker -n exercise-10
k get pods -n exercise-10
# The pod is back — kubelet recreates the mirror pod from the manifest

# Step 5: Validate
./scripts/lab.sh check 10
```

</details>
