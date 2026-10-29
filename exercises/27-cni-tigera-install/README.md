# Exercise 27 — CNI Installation (Calico/Tigera Operator)

> Related: [README — Cluster Maintenance](../../README.md#domain-7--cluster-maintenance-11)

Install a full CNI plugin using the Tigera Operator for Calico, including networking and security policies. Essential for multi-node clusters.

## Tasks

This exercise runs on the cni cluster (`./scripts/init-cluster.sh --profile cni`, then `./scripts/lab.sh setup 27`). It was created **without** a CNI plugin: both nodes are `NotReady` and CoreDNS is `Pending`. Namespace `exercise-27` exists.

1. Find the cluster's pod CIDR from the kube-controller-manager (`--cluster-cidr`) or the `kubeadm-config` ConfigMap
2. Install the Tigera Operator, Calico **v3.33.0**:
   - Create the operator CRDs (`operator-crds.yaml`) and the operator (`tigera-operator.yaml`)
   - Wait for Deployment `tigera-operator` in namespace `tigera-operator`
3. Create the Calico configuration: an `Installation` named `default` with one IPv4 pool whose CIDR matches the pod CIDR from step 1, VXLAN encapsulation (`VXLANCrossSubnet`)
4. Wait until `k get tigerastatus` shows `calico` Available and all `calico-system` pods are Ready
5. Verify node networking is operational: both nodes `Ready`, CoreDNS running
6. In namespace `exercise-27`, create Deployment `web` (2 replicas, image `nginx:1.28`, label `app=web`) and a Service `web` on port `80`; confirm that a pod on the other node (the control plane) can reach a `web` pod by its IP
7. Create NetworkPolicy `web-allow-access` in `exercise-27`: pods `app=web` accept ingress on TCP `80` only from pods labelled `access=true`. Test that it actually blocks a pod without that label

Validate with `./scripts/lab.sh check 27`.

## Key Learning

- CNI is required for pod networking between nodes
- Tigera Operator is production-grade Calico installation
- Cluster CIDR alignment is critical — mismatch breaks networking
- Exam provides the Tigera installation link
- Installation can take 2-3 minutes
- A NetworkPolicy only does something if the CNI enforces it — Calico does

## Hints

<details>
<summary>Stuck? Click to reveal hints</summary>

- Get cluster CIDR: `k -n kube-system get cm kubeadm-config -o yaml | grep -i podSubnet`
- Alternative: `k -n kube-system get pod -l component=kube-controller-manager -o yaml | grep cluster-cidr` (in the exam: `ps aux | grep kube-controller-manager | grep cidr` on the control plane)
- Tigera docs: `https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises`
- Use `k create -f` for the operator manifests, not `k apply`: the CRDs are too large for the last-applied annotation
- `custom-resources.yaml` from the same release is a ready-made `Installation` — download it, check the `cidr`, then create it
- Wait for pods: `k get pods -n calico-system -w`
- Test pod networking: `k run test --image=busybox:1.37 --rm -it --restart=Never -- wget -qO- -T 5 <pod-ip>`
- To put a test pod on the control plane: `--overrides='{"spec":{"nodeName":"cka-cni-control-plane","tolerations":[{"operator":"Exists"}]}}'`

</details>

## What tripped me up

> I forgot to check the actual cluster CIDR before installing Calico. Installed with default 192.168.0.0/16 but my cluster used 10.0.0.0/8. No inter-node networking worked. Pods on different nodes couldn't reach each other. Had to uninstall and reinstall with correct CIDR. Always grep the kube-controller-manager first. Also: Tigera operator takes time to start — don't panic if calico pods aren't running immediately. Give it 2-3 minutes.

## Verify

```bash
./scripts/lab.sh check 27
```

Manual checks:

```bash
# Operator is running
k get deployment -n tigera-operator

# Calico reports Available
k get tigerastatus
k get installation default -o jsonpath='{.spec.calicoNetwork.ipPools[*].cidr}{"\n"}'

# Calico system pods are Ready, one calico-node per node
k get pods -n calico-system -o wide
k get nodes

# Cross-node: web pods run on the worker, the test pod on the control plane
k -n exercise-27 get pods -o wide
k -n exercise-27 run x --image=busybox:1.37 --rm -it --restart=Never -l access=true \
  --overrides='{"spec":{"nodeName":"cka-cni-control-plane","tolerations":[{"operator":"Exists"}]}}' \
  -- wget -qO- -T 5 <web-pod-ip>

# NetworkPolicy works
k -n exercise-27 run ok  --image=busybox:1.37 --rm -it --restart=Never -l access=true -- wget -qO- -T 5 web   # HTML
k -n exercise-27 run bad --image=busybox:1.37 --rm -it --restart=Never -- wget -qO- -T 5 web                 # timeout
```

## Cleanup

```bash
./scripts/lab.sh cleanup 27
```

This removes namespace `exercise-27`. Calico stays: removing a CNI from a running cluster leaves the nodes broken. To practise the installation again, recreate the cluster with `./scripts/init-cluster.sh --profile cni --recreate`.

<details>
<summary>Solution</summary>

```bash
# 1. Get cluster CIDR
k -n kube-system get cm kubeadm-config -o yaml | grep -i podSubnet
# Output: podSubnet: 192.168.0.0/16
k -n kube-system get pod -l component=kube-controller-manager -o yaml | grep cluster-cidr
# Output: - --cluster-cidr=192.168.0.0/16

# 2. Install the operator CRDs and the operator (create, not apply)
k create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/operator-crds.yaml
k create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml

# 3. Wait for operator to be ready
k wait --for=condition=available --timeout=300s deployment/tigera-operator -n tigera-operator

# 4. Create Calico Installation resource with correct CIDR
#    (same as the Installation in .../v3.33.0/manifests/custom-resources.yaml)
cat <<EOF | k create -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: 192.168.0.0/16  # Must match your cluster CIDR
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# 5. Wait for Calico to be ready (2-3 minutes)
until k get tigerastatus calico >/dev/null 2>&1; do sleep 5; done   # the operator creates it after a few seconds
k wait --for=condition=Available --timeout=300s tigerastatus/calico
k get pods -n calico-system
# Should show calico-node (one per node), calico-kube-controllers, calico-typha, csi-node-driver
k get nodes                       # both Ready
k -n kube-system get pods -l k8s-app=kube-dns

# 6. Test workload + cross-node networking
k -n exercise-27 create deployment web --image=nginx:1.28 --replicas=2
k -n exercise-27 expose deployment web --port=80
k -n exercise-27 rollout status deployment web
k -n exercise-27 get pods -o wide # IPs from 192.168.0.0/16, on cka-cni-worker

POD_IP=$(k -n exercise-27 get pod -l app=web -o jsonpath='{.items[0].status.podIP}')
k -n exercise-27 run x --image=busybox:1.37 --rm -it --restart=Never \
  --overrides='{"spec":{"nodeName":"cka-cni-control-plane","tolerations":[{"operator":"Exists"}]}}' \
  -- wget -qO- -T 5 $POD_IP
# Should print the nginx welcome page

# 7. NetworkPolicy
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-access
  namespace: exercise-27
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          access: "true"
    ports:
    - protocol: TCP
      port: 80
EOF

k -n exercise-27 run ok  --image=busybox:1.37 --rm -it --restart=Never -l access=true -- wget -qO- -T 5 web   # works
k -n exercise-27 run bad --image=busybox:1.37 --rm -it --restart=Never -- wget -qO- -T 5 web                 # times out
```

Reference: https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises

</details>
