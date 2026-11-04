# Confine a Pod with an AppArmor profile

**Context:** `kubectl config use-context {{CONTEXT}}`

On node `{{NODE_W1}}` (`ssh {{NODE_W1}}`) there is an AppArmor profile in `/root/apparmor/{{PROFILE}}`. It denies all file writes.

1. Load the profile on `{{NODE_W1}}` in enforce mode.
2. Create Pod `{{POD}}` in namespace `doc-render` on node `{{NODE_W1}}` with image `busybox:1.37` and command `sleep 1d`. Its container must be confined by this profile.

## Hints

- `apparmor_parser` loads a profile file into the kernel, and `aa-status` lists the loaded profiles with their mode.
- The name Kubernetes needs is the profile name inside the file (after `profile`), not the file name.
- Since Kubernetes 1.30 the profile is set with `securityContext.appArmorProfile` (`type: Localhost`, `localhostProfile: <name>`), on the Pod or on a container. Inside the container, `cat /proc/1/attr/current` shows the profile.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_W1}}
apparmor_parser -q /root/apparmor/{{PROFILE}}       # loads in enforce mode (-C would be complain mode)
aa-status | grep {{PROFILE}}
exit
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{POD}}
  namespace: doc-render
spec:
  nodeName: {{NODE_W1}}
  containers:
  - name: main
    image: busybox:1.37
    command: ["sleep", "1d"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: {{PROFILE}}
```

```bash
k apply -f pod.yaml
k -n doc-render exec {{POD}} -- cat /proc/1/attr/current     # {{PROFILE}} (enforce)
k -n doc-render exec {{POD}} -- touch /tmp/x                 # touch: /tmp/x: Permission denied
```

The profile must be loaded on the node where the Pod runs. Otherwise the Pod is rejected with `Cannot enforce AppArmor: profile "{{PROFILE}}" is not loaded`. A profile loaded with `apparmor_parser` is gone after a reboot unless the file is also placed in `/etc/apparmor.d/`. Before Kubernetes 1.30 the profile was set with the annotation `container.apparmor.security.beta.kubernetes.io/<container>: localhost/<name>`, which is deprecated now.

In this lab the kind nodes share the kernel of your machine, so AppArmor has to be active there. On WSL2 it is off by default: see `docs/cks-wsl.md`.
