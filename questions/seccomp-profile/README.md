# Restrict syscalls with seccomp profiles

**Context:** `kubectl config use-context {{CONTEXT}}`

On node `{{NODE_W1}}` (`ssh {{NODE_W1}}`) there is a seccomp profile `/root/profiles/{{PROFILE}}.json`.

1. Install the profile on `{{NODE_W1}}` so that Pods can refer to it as `profiles/{{PROFILE}}.json`.
2. Create Pod `{{POD}}` in namespace `fintech-core` on node `{{NODE_W1}}` with image `busybox:1.37` and command `sleep 1d`. The Pod must use this profile.
3. Deployment `legacy-api` in namespace `fintech-core` runs without seccomp filtering. Change it to use the container runtime's default seccomp profile. Its Pods must be running.

## Hints

- The kubelet looks for `Localhost` profiles relative to `<kubelet root dir>/seccomp`, which is `/var/lib/kubelet/seccomp` by default.
- `securityContext.seccompProfile` has the fields `type` (`RuntimeDefault`, `Localhost`, `Unconfined`) and `localhostProfile`. It can be set on the Pod or on each container, and the container setting wins.
- The Pod stays in `CreateContainerError` if the profile file can't be found. `grep Seccomp /proc/1/status` inside a container shows `2` when a filter is active.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_W1}}
mkdir -p /var/lib/kubelet/seccomp/profiles
cp /root/profiles/{{PROFILE}}.json /var/lib/kubelet/seccomp/profiles/
exit
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{POD}}
  namespace: fintech-core
spec:
  nodeName: {{NODE_W1}}
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/{{PROFILE}}.json
  containers:
  - name: main
    image: busybox:1.37
    command: ["sleep", "1d"]
```

```bash
k apply -f pod.yaml
k -n fintech-core exec {{POD}} -- mkdir /tmp/x        # mkdir: can't create directory '/tmp/x': Operation not permitted

k -n fintech-core edit deploy legacy-api
#   spec.template.spec.securityContext.seccompProfile.type: Unconfined  ->  RuntimeDefault
k -n fintech-core rollout status deploy legacy-api
k -n fintech-core exec deploy/legacy-api -- grep Seccomp /proc/1/status      # Seccomp: 2
```

`localhostProfile` is a path relative to the kubelet's seccomp directory, not an absolute path. The profile has to be on every node where the Pod can run, so the Pod is pinned to `{{NODE_W1}}`. `RuntimeDefault` is containerd's default profile: it blocks about 50 rarely needed syscalls (`mount`, `kexec_load`, `bpf`, ...). `Unconfined` turns filtering off completely.
