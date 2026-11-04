# kubectl for the CKAD — Exam-Ready Commands

Copy-paste these. Muscle memory = speed. Test each command 3× before the exam.

---

## Aliases (Run FIRST Thing)

```bash
alias k=kubectl
export do='--dry-run=client -o yaml'      # k run nginx --image=nginx $do
export now='--force --grace-period=0'     # k delete pod nginx $now
```

---

## CREATE (Most Common)

```bash
# Pod
k run app --image=nginx
k run app --image=nginx --port=8080 --env=KEY=value

# Deployment
k create deployment app --image=nginx --replicas=3
k create deployment app --image=nginx -- command arg1

# Service
k expose deployment app --port=80 --target-port=8080 --name=app-svc
k expose pod app --port=80 --name=app-svc

# ConfigMap
k create configmap cfg --from-literal=key=value --from-literal=key2=val2
k create configmap cfg --from-file=path/to/file

# Secret
k create secret generic sec --from-literal=user=admin --from-literal=pass=secret

# ServiceAccount
k create serviceaccount app-sa

# Role
k create role app-role --verb=get,list,watch --resource=pods,services

# RoleBinding
k create rolebinding app-binding --role=app-role --serviceaccount=default:app-sa

# ClusterRole (same resource across all namespaces)
k create clusterrole admin-role --verb=* --resource=*

# ClusterRoleBinding
k create clusterrolebinding admin-binding --clusterrole=admin-role --serviceaccount=default:admin-sa

# CronJob
k create cronjob backup --image=ubuntu --schedule="0 2 * * *" -- /bin/bash -c "backup.sh"

# Job
k create job backup --image=ubuntu -- /bin/bash -c "backup.sh"
k create job mybatch --from=cronjob/mybackup  # From cronjob template

# Namespace
k create namespace prod

# NetworkPolicy (use YAML)
k apply -f networkpolicy.yaml

# Ingress (use YAML)
k create ingress myingress --class=nginx --rule="example.com/*=app-svc:80"
```

---

## GET (Inspect State)

```bash
# List all
k get all
k get all -n prod

# Specific resources
k get pod
k get deployment
k get service / svc
k get configmap
k get secret
k get serviceaccount / sa
k get role
k get rolebinding
k get networkpolicy

# Show labels (critical for debugging)
k get pod --show-labels
k get pod -L app,tier  # Show specific labels as columns

# Wide output (more details)
k get pod -o wide
k get svc -o wide

# JSON output (extract values)
k get pod -o json
k get deployment -o jsonpath='{.spec.replicas}'

# Sort by creation time
k get pod --sort-by=.metadata.creationTimestamp

# Filter by field
k get pod --field-selector=status.phase=Running

# All namespaces
k get pod -A / --all-namespaces

# Watch in real-time
k get pod -w
k get pod -w --all-namespaces
```

---

## DESCRIBE (Detailed Inspection)

```bash
# Pod events, conditions, volumes
k describe pod <name>

# Deployment rollout history, replicas
k describe deployment <name>

# Service endpoints, selectors, ports
k describe svc <name>

# Node resources, capacity
k describe node <name>

# Events (what happened)
k describe pod <name> | grep -A 10 "Events:"
```

---

## LOGS (Troubleshooting)

```bash
# Pod logs
k logs <pod-name>
k logs -f <pod-name>  # Follow (tail -f)
k logs <pod> -c <container>  # Specific container

# Previous pod logs (if pod crashed and restarted)
k logs <pod> --previous

# All pods in deployment
k logs -l app=myapp

# All containers
k logs <pod> --all-containers=true
```

---

## EDIT (Modify in Place)

```bash
# Edit resource YAML
k edit deployment <name>
k edit svc <name>
k edit cm <name>

# Edit and save = immediate effect on cluster
```

---

## SET (Modify Without Editing)

```bash
# Image
k set image deployment/app app=nginx:latest

# Replicas
k scale deployment app --replicas=5

# Env vars
k set env deployment/app KEY=value

# Resources (CPU/memory)
k set resources deployment/app --limits=cpu=500m,memory=512Mi
```

---

## DELETE (Cleanup)

```bash
# Delete pod
k delete pod <name>
k delete pod <name> -n <ns>

# Delete deployment (cascades to pods)
k delete deployment <name>

# Delete by label
k delete pod -l app=myapp

# Delete namespace (cascades everything)
k delete namespace <name>

# Force delete (skip graceful shutdown)
k delete pod <name> --force --grace-period=0
```

---

## EXEC / PORT-FORWARD (Testing)

```bash
# Execute command in pod
k exec -it <pod> -- /bin/bash
k exec <pod> -- curl http://localhost:8080

# Port forward (access service locally)
k port-forward svc/<svc-name> 8080:80
k port-forward pod/<pod-name> 8080:8080

# After port-forward, in another terminal:
curl localhost:8080
```

---

## APPLY (Declarative)

```bash
# Apply YAML file
k apply -f deployment.yaml

# Apply all YAML in directory
k apply -f ./manifests/

# Dry-run (test without applying)
k apply -f deployment.yaml --dry-run=client

# Output what would be created
k apply -f deployment.yaml --dry-run=client -o yaml
```

---

## LABEL / PATCH (Modify)

```bash
# Add label to pod
k label pod <pod-name> app=myapp

# Modify label (overwrite)
k label pod <pod-name> app=otherapp --overwrite

# Remove label (add -)
k label pod <pod-name> tier-

# Patch (JSON merge)
k patch deployment app -p '{"spec":{"replicas":5}}'
```

---

## AUTH / RBAC (Verify Permissions)

```bash
# Can I...?
k auth can-i get pods
k auth can-i delete deployments

# As ServiceAccount...?
k auth can-i get pods --as=system:serviceaccount:default:app-sa

# In namespace...?
k auth can-i list pods -n prod --as=system:serviceaccount:prod:reader
```

---

## CONTEXT / CLUSTER (Navigation)

```bash
# Current context
k config current-context

# List contexts
k config get-contexts

# Switch context
k config use-context <name>

# View kubeconfig
k config view

# Current namespace
k config get-contexts | grep "*"

# Set default namespace (survives terminal restart if in kubeconfig)
k config set-context --current --namespace=prod

# Quick namsepace switch
alias kn='k config set-context --current --namespace'
kn prod  # Switch to prod
kn default  # Switch back
```

---

## EXPLAIN (Quick Docs in Exam)

```bash
# Explain resource fields
k explain pod
k explain pod.spec
k explain deployment.spec.template.spec

# Full recursive
k explain pod --recursive
```

---

## DEBUG / EVENTS

```bash
# Cluster events (what happened recently)
k get events -A

# Events in namespace
k get events -n prod

# Events for specific pod
k get events --field-selector involvedObject.name=<pod-name>

# Troubleshooting pod
k get pod <name> -o yaml | grep -A 20 "status:"
```

---

## One-Liners for Speed

```bash
# Show all pods with their IP and node
k get pod -o wide -A

# List all resources that need attention
k get pod,svc,deployment --no-headers

# Check cluster health
k get nodes
k get componentstatuses

# Find pods on a specific node
k get pod --field-selector=spec.nodeName=<node>

# Show resource consumption (if metrics-server running)
k top nodes
k top pod

# Quick RBAC audit
k get clusterrole
k get clusterrolebinding
k get role -A
k get rolebinding -A
```

---

## Muscle-Memory Commands (Practice 5× Each)

These come up across many task types:

```bash
# 1. Create + Expose
k create deployment api --image=nginx --replicas=2 $do | k apply -f -
k expose deployment api --port=8080 --name=api-svc

# 2. Check Endpoints (diagnose selector mismatch)
k get svc api-svc -o wide
k get endpoints api-svc

# 3. RBAC Trio
k create sa reader
k create role pod-reader --verb=get,list --resource=pods
k create rolebinding pod-reader-binding --role=pod-reader --serviceaccount=default:reader

# 4. Verify Permissions
k auth can-i get pods --as=system:serviceaccount:default:reader

# 5. Debug Pod Crash
k describe pod <name>
k logs <name>
k logs <name> --previous
```

---

## Time-Saving Keyboard Tips

- `Tab` key = autocomplete (use HEAVILY)  
- `Ctrl+C` = cancel running command
- `Ctrl+L` = clear screen  
- `↑` arrow = previous command  
- `k edit` = faster than YAML files

Practice these commands 10× each before exam.

