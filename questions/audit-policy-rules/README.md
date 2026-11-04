# Audit log forensics and a fine-grained audit policy

**Context:** `kubectl config use-context {{CONTEXT}}`

Audit logging is already enabled on the kube-apiserver of `{{NODE_CP}}` (`ssh {{NODE_CP}}`): the policy `/etc/kubernetes/audit/policy.yaml` logs every request at level `Metadata` to `/var/log/kubernetes/audit/audit.log`.

1. Somebody deleted the Secret `db-backup-key` in namespace `payroll`. Find out from the audit log which account did it and write its username, exactly as the audit log records it, into `{{WORKDIR}}/deleted-by.txt` on your exam host.
2. The log is far too noisy. Replace the policy in `/etc/kubernetes/audit/policy.yaml` (keep the file and the kube-apiserver flags) so that:
   - the stage `RequestReceived` is never logged,
   - Secrets are logged at level `Metadata` (all verbs, all namespaces),
   - creating, updating, patching or deleting Pods in namespace `payroll` is logged at level `RequestResponse`,
   - all other `get`, `list` and `watch` requests are not logged,
   - everything else is logged at level `Metadata`.
3. Make sure the kube-apiserver uses the new policy and is running.

## Hints

- Every audit event is one JSON line with `verb`, `objectRef` (`resource`, `namespace`, `name`) and `user.username`. `grep db-backup-key audit.log | grep '"verb":"delete"'`, and `jq` is installed on the node.
- Rules are evaluated in order and the first match wins: the Secrets rule must come before the rule that drops `get`/`list`/`watch`. `omitStages` can be set for the whole policy, `namespaces` and `verbs` per rule.
- The kube-apiserver reads the policy file only when it starts. Changing the file alone changes nothing; restart the API server, e.g. by moving its manifest out of `/etc/kubernetes/manifests/` and back.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
grep '"name":"db-backup-key"' /var/log/kubernetes/audit/audit.log | grep '"verb":"delete"' | jq -r '.user.username' | sort -u
# system:serviceaccount:payroll:{{CULPRIT}}
exit
echo system:serviceaccount:payroll:{{CULPRIT}} > {{WORKDIR}}/deleted-by.txt

ssh {{NODE_CP}}
cat > /etc/kubernetes/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages:
- RequestReceived
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]
- level: RequestResponse
  namespaces: ["payroll"]
  verbs: ["create", "update", "patch", "delete"]
  resources:
  - group: ""
    resources: ["pods"]
- level: None
  verbs: ["get", "list", "watch"]
- level: Metadata
EOF

# restart the API server so it reads the policy again
mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/
crictl ps --name kube-apiserver          # wait until it is gone
mv /root/kube-apiserver.yaml /etc/kubernetes/manifests/
watch crictl ps --name kube-apiserver    # running again after 30-60s
tail -n 3 /var/log/kubernetes/audit/audit.log
```

Each request appears twice in the log (stages `RequestReceived` and `ResponseComplete`), hence the `sort -u`. The delete event carries the account that sent the request in `user.username`; for a ServiceAccount that is `system:serviceaccount:<namespace>:<name>`. Only the `delete` of `db-backup-key` counts: the other bots read the Secret, and one deleted a different Secret. In the policy the order matters: with the `get`/`list`/`watch` rule first, reading a Secret would no longer be logged. `RequestResponse` for Pods records the full pod spec of every change in `payroll`, which shows exactly what was deployed. Secrets stay at `Metadata` on purpose: a higher level would write their values into the log. The restart is the step people forget: until the API server starts again, it keeps using the policy it loaded at startup.
