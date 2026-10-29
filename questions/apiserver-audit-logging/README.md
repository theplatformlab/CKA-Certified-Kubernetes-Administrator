# API server audit logging

**Context:** `kubectl config use-context {{CONTEXT}}`

Enable audit logging on the kube-apiserver of node `{{NODE_CP}}` (`ssh {{NODE_CP}}`).

1. Create the audit policy `/etc/kubernetes/audit/policy.yaml` with these rules:
   - Secrets in all namespaces are logged at level `Metadata`.
   - ConfigMaps in namespace `default` are logged at level `Request`.
   - Nothing else is logged.
2. Configure the kube-apiserver to:
   - use that policy file
   - write the log to `/var/log/kubernetes/audit/audit.log`
   - keep logs for at most `7` days
   - keep at most `3` old log files
3. The kube-apiserver must be running again afterwards.

## Hints

- The Auditing page on kubernetes.io has a complete policy example and the list of `--audit-*` flags.
- Rules are evaluated in order, first match wins: specific rules first, the catch-all `level: None` last.
- The API server runs in a container: the policy file and the log directory need hostPath volumes and volumeMounts in the static pod manifest.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]
- level: Request
  namespaces: ["default"]
  resources:
  - group: ""
    resources: ["configmaps"]
- level: None
EOF
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=7
    - --audit-log-maxbackup=3
    # ... existing flags ...
    volumeMounts:
    - name: audit-policy
      mountPath: /etc/kubernetes/audit
      readOnly: true
    - name: audit-log
      mountPath: /var/log/kubernetes/audit
  volumes:
  - name: audit-policy
    hostPath:
      path: /etc/kubernetes/audit
      type: DirectoryOrCreate
  - name: audit-log
    hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
```

```bash
# wait for the apiserver to come back (30-60s)
watch crictl ps --name kube-apiserver
tail -n 2 /var/log/kubernetes/audit/audit.log
```

Rule order matters: the first rule that matches wins, so the catch-all `level: None` goes last. Without the volume mounts, the apiserver can't read the policy or write the log, and it won't start. If it doesn't come back, check `crictl ps -a` and `crictl logs <id>`, or `/var/log/pods/kube-system_kube-apiserver-*`.
