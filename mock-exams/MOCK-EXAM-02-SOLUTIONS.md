# Mock Exam 02 — Solutions

Don't read this before you finish the exam. Grade first (`./scripts/mock-exam.sh grade`), then compare.

---

## Question 1 — Service discovery and DNS

```bash
k config use-context kind-cka-exam
echo web-ui.frontend.svc.cluster.local > ~/cka-exam/q01/dns.txt

k -n backend run dns-test --image=busybox:1.37 --command -- sleep 3600
k -n backend wait --for=condition=Ready pod/dns-test
k -n backend exec dns-test -- nslookup web-ui.frontend.svc.cluster.local > ~/cka-exam/q01/nslookup.txt
cat ~/cka-exam/q01/nslookup.txt
```

The pattern is `<service>.<namespace>.svc.<cluster-domain>`, and the cluster domain is `cluster.local` unless the kubelet sets it otherwise (`clusterDomain` in `/var/lib/kubelet/config.yaml`). Inside the same namespace, `web-ui` alone works. From another namespace, `web-ui.frontend` works too, thanks to the search domains in the pod's `/etc/resolv.conf`.

---

## Question 2 — Roll back a broken rollout

```bash
k config use-context kind-cka-exam
k -n payments rollout history deploy payment-service
# REVISION  CHANGE-CAUSE
# 1         initial release nginx:1.27
# 2         upgrade to nginx:1.28
# 3         upgrade to nginx:1.28.99      <- ImagePullBackOff
k -n payments rollout history deploy payment-service --revision=3   # confirm the image
echo 3 > ~/cka-exam/q02/broken-revision.txt

k -n payments rollout undo deploy payment-service --to-revision=2
k -n payments rollout status deploy payment-service
```

`rollout undo` without `--to-revision` also goes back exactly one revision. Spelling out the target is safer when you are under pressure. After the undo, revision 2 is renumbered to 4: the history only ever moves forward.

---

## Question 3 — Secrets as environment variables

```bash
k config use-context kind-cka-exam
k -n apps create secret generic db-credentials \
  --from-literal=DB_USER=dbuser --from-literal=DB_PASSWORD=secret123 --from-literal=DB_NAME=appdb
k -n apps create deployment db-client --image=busybox:1.37 $do -- sleep 3600 > db-client.yaml
```

Add `envFrom` to the container:

```yaml
    spec:
      containers:
      - name: busybox
        image: busybox:1.37
        command: ["sleep", "3600"]
        envFrom:
        - secretRef:
            name: db-credentials
```

```bash
k apply -f db-client.yaml
k -n apps exec deploy/db-client -- printenv DB_USER DB_NAME
```

Alternatively, `k -n apps set env deploy/db-client --from=secret/db-credentials` creates three `secretKeyRef` entries. Both reference the Secret instead of copying its values. That is what "no secret values in the manifest" means.

---

## Question 4 — DaemonSet on all nodes

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: busybox:1.37
        command: ["sleep", "86400"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
```

There is no `kubectl create daemonset`. Generate a Deployment with `$do`, then change `kind`, and remove `replicas` and `strategy`. Without the toleration you get 2 of 3 pods. The control plane's `NoSchedule` taint keeps the third one away.

---

## Question 5 — API server is down

```bash
k config use-context kind-cka-exam-ops
k get nodes                     # connection refused
ssh cka-exam-ops-control-plane
crictl ps -a --name kube-apiserver       # Exited, restarting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1)
# ... unable to load client CA provider: open /etc/kubernetes/pki/client-ca.crt: no such file or directory

ls /etc/kubernetes/pki/                   # ca.crt exists
sed -i 's|--client-ca-file=/etc/kubernetes/pki/client-ca.crt|--client-ca-file=/etc/kubernetes/pki/ca.crt|' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
watch crictl ps --name kube-apiserver
exit
k get nodes
```

When the API server is down, `kubectl logs` is useless. Use `crictl logs` on the node, or read `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log`. If the container doesn't even get created (YAML syntax error), the kubelet logs show why: `journalctl -u kubelet | grep apiserver`.

---

## Question 6 — ConfigMap changes and running pods

```bash
k config use-context kind-cka-exam
k -n config-demo patch cm app-config -p '{"data":{"mode":"production","message":"v2"}}'
k -n config-demo rollout restart deploy config-app
k -n config-demo rollout status deploy config-app
k -n config-demo exec deploy/config-app -- sh -c 'echo $APP_MODE; cat /etc/app/message'
```

Mounted ConfigMap files are updated in place by the kubelet after up to about a minute (not with `subPath`). Environment variables are only read when the container starts. So the env var needs new pods, and `rollout restart` gives you that without deleting the Deployment.

---

## Question 7 — PriorityClasses

```bash
k config use-context kind-cka-exam
k create priorityclass critical-workload --value=1000000 --description=critical
k create priorityclass standard-workload --value=1000 --preemption-policy=Never

k -n priority create deployment critical-app --image=busybox:1.37 --replicas=2 $do -- sleep 3600 > critical.yaml
# add  spec.template.spec.priorityClassName: critical-workload
k apply -f critical.yaml

k -n priority run batch-job --image=busybox:1.37 $do --command -- sleep 3600 > batch.yaml
# add  spec.priorityClassName: standard-workload
k apply -f batch.yaml
k -n priority get pods -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority
```

The admission controller turns `priorityClassName` into the numeric `spec.priority` at creation. `preemptionPolicy: Never` means pods of that class never evict others to get scheduled, but they can still be preempted themselves.

---

## Question 8 — Expose an application with a NodePort

```bash
k config use-context kind-cka-exam
k -n legacy expose deploy legacy-app --name=legacy-svc --type=NodePort --port=8080 --target-port=3000 $do > svc.yaml
# add  nodePort: 30080  under spec.ports[0]
k apply -f svc.yaml

k get nodes -o wide                                    # pick an INTERNAL-IP
k run t --rm -it --image=busybox:1.37 --restart=Never -- wget -qO- <node-ip>:30080
```

`kubectl create service nodeport legacy-svc --tcp=8080:3000 --node-port=30080` would select `app=legacy-svc`, which matches nothing here. `expose` copies the Deployment's selector, so prefer it.

---

## Question 9 — CronJob

```bash
k config use-context kind-cka-exam
k -n backup create cronjob db-backup --image=busybox:1.37 --schedule="0 2 * * *" $do \
  -- sh -c 'echo backup done' > cj.yaml
```

```yaml
spec:
  schedule: "0 2 * * *"
  suspend: true
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    # ... unchanged ...
```

```bash
k apply -f cj.yaml
k -n backup create job db-backup-manual --from=cronjob/db-backup
k -n backup wait --for=condition=Complete job/db-backup-manual
k -n backup logs job/db-backup-manual
```

`--from=cronjob/...` works even while the CronJob is suspended. `suspend` only stops the scheduler from creating Jobs.

---

## Question 10 — Renew control plane certificates

```bash
k config use-context kind-cka-exam-ops
ssh cka-exam-ops-control-plane
kubeadm certs check-expiration | grep -w apiserver
# apiserver   Oct 28, 2027 21:12 UTC   364d   ca   no
exit
echo "Oct 28, 2027 21:12 UTC" > ~/cka-exam/q10/expiration.txt     # on the exam host

ssh cka-exam-ops-control-plane
kubeadm certs renew all
# "You must restart the kube-apiserver, kube-controller-manager, kube-scheduler and etcd"
mkdir -p /root/manifests-tmp
mv /etc/kubernetes/manifests/*.yaml /root/manifests-tmp/
sleep 20                                     # wait until crictl ps shows them gone
mv /root/manifests-tmp/*.yaml /etc/kubernetes/manifests/
kubeadm certs check-expiration
exit
```

`kubeadm certs renew` only rewrites the files. The static pods keep the old certificates in memory until they restart. Moving the manifests out and back in is the standard way to restart them. `admin.conf` is renewed too, so copy it again if you use it as your kubeconfig.

---

## Question 11 — PodDisruptionBudget

```bash
k config use-context kind-cka-exam
k -n web create pdb frontend-pdb --selector=app=frontend --max-unavailable=2
k -n web get pdb frontend-pdb       # ALLOWED DISRUPTIONS 2
```

`--min-available=8` would behave the same with 10 replicas, but the question asks for `maxUnavailable`, so the grader checks that field. Try it: `k drain <worker> --ignore-daemonsets` now evicts at most 2 frontend pods at a time and waits for replacements.

---

## Question 12 — Custom resources

```bash
k config use-context kind-cka-exam
k explain databases.spec --api-version=example.com/v1
k apply -f - <<'EOF'
apiVersion: example.com/v1
kind: Database
metadata:
  name: orders-db
  namespace: team-data
spec:
  engine: postgres
  version: "17"
  storageGB: 20
EOF
k -n team-data delete database legacy-db
k get crd -o name | grep '\.example\.com$' | cut -d/ -f2 > ~/cka-exam/q12/crds.txt
```

Quote `version: "17"`. The schema declares it as a string, and an unquoted `17` is rejected. Use `grep '\.example\.com$'`, not `grep example.com`, which would also match a group like `notexample.com`.

---

## Question 13 — Pod Security Admission

```bash
k config use-context kind-cka-exam
k create ns secure-apps
k label ns secure-apps pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
  namespace: secure-apps
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: web
    image: nginxinc/nginx-unprivileged:1.28-alpine
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

```bash
k apply -f restricted-pod.yaml
k -n secure-apps run blocked-pod --image=busybox:1.37 \
  --overrides='{"spec":{"containers":[{"name":"blocked-pod","image":"busybox:1.37","command":["sleep","3600"],"securityContext":{"privileged":true}}]}}' \
  2> ~/cka-exam/q13/error.txt
cat ~/cka-exam/q13/error.txt
# Error from server (Forbidden): pods "blocked-pod" is forbidden: violates PodSecurity "restricted:latest": privileged ...
```

The error goes to stderr, so use `2>`. With `>` you capture nothing.

---

## Question 14 — StorageClass and default class

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

```bash
k config use-context kind-cka-exam
k apply -f sc.yaml
k patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
k get sc                     # only local-ssd shows (default)
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: storage
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: data-pod
  namespace: storage
spec:
  containers:
  - name: web
    image: nginx:1.28
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc
```

Order matters. The default class is filled into a PVC when it is created, so a PVC created before you switch the default keeps `standard`. With two defaults, Kubernetes uses the newest one, but don't rely on that: remove the old default explicitly.

---

## Question 15 — Namespace resource governance

```bash
k config use-context kind-cka-exam
k -n batch-jobs create quota batch-quota \
  --hard=requests.cpu=10,requests.memory=20Gi,limits.cpu=10,limits.memory=20Gi,pods=20
```

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: batch-limits
  namespace: batch-jobs
spec:
  limits:
  - type: Container
    min:
      cpu: 500m
      memory: 256Mi
    max:
      cpu: "4"
      memory: 8Gi
    defaultRequest:
      cpu: 500m
      memory: 256Mi
    default:
      cpu: 500m
      memory: 256Mi
```

```bash
k apply -f lr.yaml
k -n batch-jobs run big --image=busybox:1.37 \
  --overrides='{"spec":{"containers":[{"name":"big","image":"busybox:1.37","resources":{"requests":{"cpu":"5"},"limits":{"cpu":"5"}}}]}}'
# Error ... maximum cpu usage per Container is 4, but limit is 5
```

---

## Question 16 — Gateway API traffic splitting

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: gateway
spec:
  gatewayClassName: exam-gateway
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: web.example.com
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: gateway
spec:
  parentRefs:
  - name: web-gateway
  hostnames:
  - web.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-v1
      port: 80
      weight: 80
    - name: web-v2
      port: 80
      weight: 20
```

```bash
k config use-context kind-cka-exam
k apply -f gateway.yaml
k -n gateway describe httproute web-route
```

No controller implements `exam-gateway`, so the Gateway's status stays `Unknown`. Only the resources are graded. On the real exam a controller (for example NGINX Gateway Fabric or Envoy Gateway) would program the routes. The Gateway API docs (gateway-api.sigs.k8s.io) are allowed during the exam.
