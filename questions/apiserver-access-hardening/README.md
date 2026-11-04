# Restrict access to the API server

**Context:** `kubectl config use-context {{CONTEXT}}`

A CIS scan of cluster `{{CLUSTER}}` flagged the kube-apiserver on `{{NODE_CP}}` (`ssh {{NODE_CP}}`). Fix its configuration:

1. Right now anyone who reaches port 6443 can read the cluster without credentials: `curl -k https://127.0.0.1:6443/api/v1/namespaces` on the node works. Requests without credentials (anonymous requests) must be rejected with `401 Unauthorized` on every path, for example `/version` and `/api/v1/namespaces`. The only exception are the health endpoints `/livez`, `/readyz` and `/healthz`: the kubelet's probes of the kube-apiserver pod call them without credentials, so they must keep answering anonymous requests.
2. Delete the ClusterRoleBinding `anonymous-readonly` that grants anonymous users read access.
3. The API server accepts static bearer tokens from a token file, one of them with full admin rights. Remove the static token authentication and delete the token file.
4. Enable the admission plugin `NodeRestriction`.

The kube-apiserver must be running and its pod `Ready` afterwards.

## Hints

- `grep -E 'anonymous|token-auth|admission' /etc/kubernetes/manifests/kube-apiserver.yaml` shows the flags involved. `k get clusterrolebindings -o wide | grep anonymous` finds the binding.
- Try `--anonymous-auth=false` first and watch the kube-apiserver pod: `k -n kube-system get pod kube-apiserver-{{NODE_CP}}`. Its probes get `401` too, it never becomes Ready, and the startup probe eventually restarts it.
- Since v1.32 an `AuthenticationConfiguration` file (`--authentication-config`, API `apiserver.config.k8s.io/v1`) can allow anonymous requests only for some paths: `anonymous.enabled: true` with `conditions` listing the paths. The file replaces `--anonymous-auth`: the API server refuses to start when both configure anonymous access.
- A file the API server reads must be mounted into its static pod (hostPath volume and volumeMount). Keep a copy of the manifest outside `/etc/kubernetes/manifests/`; logs of a failing start are in `/var/log/pods/kube-system_kube-apiserver-*` or `crictl logs`.

## Solution

```bash
k config use-context {{CONTEXT}}
ssh {{NODE_CP}}
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
mkdir -p /etc/kubernetes/auth
cat > /etc/kubernetes/auth/authn.yaml <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
anonymous:
  enabled: true
  conditions:
  - path: /livez
  - path: /readyz
  - path: /healthz
EOF
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --authentication-config=/etc/kubernetes/auth/authn.yaml   # replaces --anonymous-auth=true (delete that line)
    - --enable-admission-plugins=NodeRestriction
    # delete: - --token-auth-file=/etc/kubernetes/pki/static-tokens.csv
    # ... other flags unchanged ...
    volumeMounts:
    - name: auth-config
      mountPath: /etc/kubernetes/auth
      readOnly: true
    # ... existing mounts ...
  volumes:
  - name: auth-config
    hostPath:
      path: /etc/kubernetes/auth
      type: DirectoryOrCreate
  # ... existing volumes ...
```

```bash
rm /etc/kubernetes/pki/static-tokens.csv
watch crictl ps --name kube-apiserver                              # new container, stays up
curl -k https://127.0.0.1:6443/version                             # 401 Unauthorized
curl -k https://127.0.0.1:6443/readyz                              # ok
exit
k delete clusterrolebinding anonymous-readonly
k -n kube-system get pod kube-apiserver-{{NODE_CP}}                # 1/1 Running (status can lag ~1 min)
```

With plain `--anonymous-auth=false` the API server works for kubectl, but the kubelet's HTTPS probes (`/livez`, `/readyz` without a client certificate) get `401`, so the pod stays `0/1` and is restarted once the startup probe gives up. The `AuthenticationConfiguration` keeps anonymous access only for the listed paths; every other path (including `/version`, which kubeadm normally exposes to `system:unauthenticated`) now needs credentials. Static token files (`--token-auth-file`) hold long-lived bearer tokens in plain text that can only be revoked by restarting the API server; the CIS benchmark requires them to be off. Deleting the ClusterRoleBinding as well is defense in depth: should anonymous access ever be turned back on, it gets nothing. `NodeRestriction` limits a kubelet to its own Node and the pods bound to it, and stops it from setting `node-restriction.kubernetes.io/` labels on itself.
