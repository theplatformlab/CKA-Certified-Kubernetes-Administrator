# kubectl for the CKS

Security-focused commands by task and the docs pages worth finding fast.

---

## kubectl Security Cheat Sheet for CKS

The commands needed most during the exam. All using the aliases from the setup section.

### Context and Namespace

```bash
# Switch context (DO THIS BEFORE EVERY QUESTION)
k config use-context <context-name>

# Set default namespace
kn <namespace>

# Check current context
k config current-context
```

### RBAC

```bash
# Create ServiceAccount
k create sa my-sa -n my-ns

# Create Role
k create role pod-reader --verb=get,list,watch --resource=pods -n my-ns

# Create RoleBinding
k create rolebinding read-pods --role=pod-reader --serviceaccount=my-ns:my-sa -n my-ns

# Create ClusterRole
k create clusterrole node-reader --verb=get,list --resource=nodes

# Create ClusterRoleBinding
k create clusterrolebinding read-nodes --clusterrole=node-reader --serviceaccount=my-ns:my-sa

# Check permissions
k auth can-i list pods -n my-ns --as=system:serviceaccount:my-ns:my-sa
k auth can-i get secrets --as=system:serviceaccount:default:default
k auth can-i '*' '*' --as=system:serviceaccount:kube-system:default
```

### NetworkPolicy

```bash
# List policies
k get networkpolicy -n <namespace>
k describe networkpolicy <name> -n <namespace>

# Test connectivity between pods
k exec <pod-a> -- wget -qO- --timeout=2 http://<pod-b-ip>:<port>
k exec <pod-a> -- nc -zv <pod-b-ip> <port>

# Quick default deny all
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

### Secrets

```bash
# Create secret
k create secret generic my-secret --from-literal=key=value -n my-ns

# Create TLS secret
k create secret tls tls-secret --cert=tls.crt --key=tls.key

# View secret (decoded)
k get secret my-secret -o jsonpath='{.data.key}' | base64 -d

# Check if secrets are encrypted at rest
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep encryption-provider-config
```

### Pod Security

```bash
# Check pod security context
k get pod <pod> -o jsonpath='{.spec.securityContext}'
k get pod <pod> -o jsonpath='{.spec.containers[*].securityContext}'

# Label namespace for Pod Security Admission
k label ns <namespace> pod-security.kubernetes.io/enforce=restricted
k label ns <namespace> pod-security.kubernetes.io/audit=restricted
k label ns <namespace> pod-security.kubernetes.io/warn=restricted

# Check namespace labels
k get ns <namespace> --show-labels
```

### Image Scanning

```bash
# Scan an image with Trivy
trivy image nginx:1.27
trivy image --severity CRITICAL,HIGH nginx:1.27
trivy image --severity CRITICAL nginx:1.27 --quiet

# Scan a Dockerfile
trivy config Dockerfile
```

### Audit Logging

```bash
# Check if audit logging is enabled
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep audit

# View audit logs
cat /var/log/kubernetes/audit/audit.log | jq .
tail -f /var/log/kubernetes/audit/audit.log | jq 'select(.verb=="create")'

# Check which API calls a user made
cat /var/log/kubernetes/audit/audit.log | jq 'select(.user.username=="system:serviceaccount:default:default")'
```

### Falco

```bash
# Check Falco status
systemctl status falco
journalctl -u falco --no-pager | tail -30

# View Falco alerts
cat /var/log/syslog | grep falco
journalctl -u falco -f

# Falco rules location
ls /etc/falco/
cat /etc/falco/falco_rules.yaml
cat /etc/falco/rules.d/
```

### Quick YAML Generation

```bash
# Pod
k run nginx --image=nginx:1.27 $do > pod.yaml

# Pod with security context
k run secure --image=nginx:1.27 $do > pod.yaml
# Then edit to add securityContext

# Service
k expose pod nginx --port=80 $do > svc.yaml

# ServiceAccount
k create sa my-sa $do > sa.yaml

# Role
k create role pod-reader --verb=get,list --resource=pods $do > role.yaml

# Secret
k create secret generic my-secret --from-literal=pass=s3cret $do > secret.yaml
```

---

## Docs Pages Worth Bookmarking

You can access kubernetes.io during the exam. These are the pages worth knowing how to find quickly:

| Topic | Page |
|---|---|
| kubectl cheat sheet | https://kubernetes.io/docs/reference/kubectl/cheatsheet/ |
| NetworkPolicy | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| Pod Security Admission | https://kubernetes.io/docs/concepts/security/pod-security-admission/ |
| Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| Audit logging | https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/ |
| Secrets | https://kubernetes.io/docs/concepts/configuration/secret/ |
| Encrypt data at rest | https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/ |
| SecurityContext | https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| AppArmor | https://kubernetes.io/docs/tutorials/security/apparmor/ |
| Seccomp | https://kubernetes.io/docs/tutorials/security/seccomp/ |
| RuntimeClass | https://kubernetes.io/docs/concepts/containers/runtime-class/ |
| ServiceAccount | https://kubernetes.io/docs/concepts/security/service-accounts/ |
| Ingress TLS | https://kubernetes.io/docs/concepts/services-networking/ingress/#tls |
| ValidatingAdmissionPolicy | https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/ |
| Falco docs (external) | https://falco.org/docs/ |
| Trivy docs (external) | https://aquasecurity.github.io/trivy/ |

Tip: use the search bar on kubernetes.io. Don't waste time clicking through navigation menus. For Falco and Trivy, the exam environment may have man pages or `--help` output — use those during the exam since external docs aren't accessible.
