# Find a misbehaving Pod with Falco and add a rule

**Context:** `kubectl config use-context {{CONTEXT}}`

Falco runs as the systemd service `falco` on node `{{NODE_W1}}` (`ssh {{NODE_W1}}`). Its rules are in `/etc/falco`.

One of the Pods in namespace `shop-backend` keeps reading `/etc/shadow`.

1. Use the Falco alerts to find this Pod. Write its name (just the Pod name) into `{{WORKDIR}}/falco-incident.txt` on your exam host.
2. Scale the Deployment that owns the Pod to `0` replicas. Leave the other Deployments running.
3. Add a custom Falco rule that fires whenever a shell (`sh`, `bash` or `ash`) is started in a container, with priority `WARNING` and exactly this output format:

   ```
   Shell in container: user=%user.name pod=%k8s.pod.name ns=%k8s.ns.name cmd=%proc.cmdline
   ```

   Don't change `/etc/falco/falco_rules.yaml`. Falco must be running with the new rule.

## Hints

- Falco logs its alerts to the journal: `journalctl -u falco`. Each alert ends with `k8s_pod_name=` and `k8s_ns_name=`.
- The alert for reading `/etc/shadow` comes from the rule `Read sensitive file untrusted`. Its output starts with `Sensitive file opened for reading by non-trusted program`.
- Custom rules go into `/etc/falco/falco_rules.local.yaml`, which is loaded after the default rules. The default rules file has the macro `spawned_process` and the list `shell_binaries`, and you can use both. Falco reloads when a rules file changes. A syntax error shows up in `journalctl -u falco`. `falco -V /etc/falco/falco_rules.yaml -V /etc/falco/falco_rules.local.yaml` validates both files together.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_W1}}
journalctl -u falco --no-pager | grep -F /etc/shadow | grep 'k8s_ns_name=shop-backend' | tail -3
# ... Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow ...
#     process=cat ... k8s_pod_name={{BAD}}-6d9f8b7c5d-x2k4q k8s_ns_name=shop-backend
exit

echo {{BAD}}-6d9f8b7c5d-x2k4q > {{WORKDIR}}/falco-incident.txt     # the Pod name from the alert
k -n shop-backend get pod {{BAD}}-6d9f8b7c5d-x2k4q -o jsonpath='{.metadata.ownerReferences[0].name}{"\n"}'   # the ReplicaSet
k -n shop-backend scale deploy {{BAD}} --replicas=0
```

```bash
ssh {{NODE_W1}}
cat >> /etc/falco/falco_rules.local.yaml <<'EOF2'
- rule: Shell in container
  desc: A shell was started in a container
  condition: spawned_process and container and proc.name in (shell_binaries)
  output: "Shell in container: user=%user.name pod=%k8s.pod.name ns=%k8s.ns.name cmd=%proc.cmdline"
  priority: WARNING
EOF2
falco -V /etc/falco/falco_rules.yaml -V /etc/falco/falco_rules.local.yaml   # optional: validate
systemctl restart falco                        # Falco also reloads on its own
exit

k -n shop-backend exec deploy/cart -- sh -c 'echo hi'
ssh {{NODE_W1}} "journalctl -u falco --no-pager --since -1min | grep 'Shell in container'"
```

The Falco alert gives the Pod name and namespace. The Pod belongs to a ReplicaSet, which belongs to the Deployment, so scale the Deployment, not the Pod: a deleted Pod would just be recreated. `spawned_process` matches successful `execve` calls, and `container` excludes processes on the host. The list `shell_binaries` already contains `sh`, `bash`, `ash` and other shells. Falco appends the container fields (`container_id=...`, `k8s_pod_name=...`) to every output, so the line is longer than the format you set.
