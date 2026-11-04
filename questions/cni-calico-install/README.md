# Install Calico with the Tigera operator

**Context:** `kubectl config use-context {{CONTEXT}}`

Cluster `{{CLUSTER}}` was created without a CNI plugin: its nodes are `NotReady` and CoreDNS is `Pending`.

1. Install Calico v3.33.0 with the Tigera operator: create the operator CRDs (`operator-crds.yaml`) and the operator (`tigera-operator.yaml`) from the Calico release manifests.
2. Create an `Installation` named `default` with one IPv4 pool whose CIDR matches the cluster's pod CIDR, using VXLAN encapsulation (`VXLANCrossSubnet`).
3. `TigeraStatus` `calico` must be Available, all nodes `Ready` and CoreDNS running.
4. In namespace `calico-test`, create Deployment `web` (2 replicas, image `nginx:1.28`, label `app=web`) and a Service `web` on port `80`. A pod on `{{NODE_CP}}` must be able to reach a `web` pod by its IP.
5. Create NetworkPolicy `web-allow-access` in `calico-test`: pods with `app=web` accept ingress on TCP port `80` only from pods labelled `access=true`.

## Hints

- The pod CIDR is in the `kubeadm-config` ConfigMap in `kube-system` (`podSubnet`), or in the `--cluster-cidr` flag of kube-controller-manager.
- Use `k create -f <url>` for the operator manifests, not `k apply`: the CRDs are too large for the last-applied annotation. `custom-resources.yaml` from the same release is a ready-made `Installation`; check its `cidr` before creating it.
- To put a test pod on the control plane node: `--overrides='{"spec":{"nodeName":"{{NODE_CP}}","tolerations":[{"operator":"Exists"}]}}'`. Calico takes 2-3 minutes to become Available.

## Solution

```bash
k config use-context {{CONTEXT}}

# 1. pod CIDR
k -n kube-system get cm kubeadm-config -o yaml | grep -i podSubnet     # podSubnet: 192.168.0.0/16

# 2. operator CRDs and operator (create, not apply)
k create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/operator-crds.yaml
k create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/tigera-operator.yaml
k -n tigera-operator wait --for=condition=available --timeout=300s deployment/tigera-operator

# 3. Installation (same as the one in .../v3.33.0/manifests/custom-resources.yaml)
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
      cidr: 192.168.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

until k get tigerastatus calico >/dev/null 2>&1; do sleep 5; done
k wait --for=condition=Available --timeout=300s tigerastatus/calico
k get pods -n calico-system
k get nodes                                    # all Ready
k -n kube-system get pods -l k8s-app=kube-dns

# 4. workload and cross-node test
k -n calico-test create deployment web --image=nginx:1.28 --replicas=2
k -n calico-test expose deployment web --port=80
k -n calico-test rollout status deployment web
POD_IP=$(k -n calico-test get pod -l app=web -o jsonpath='{.items[0].status.podIP}')
k -n calico-test run x --image=busybox:1.37 --rm -it --restart=Never \
  --overrides='{"spec":{"nodeName":"{{NODE_CP}}","tolerations":[{"operator":"Exists"}]}}' \
  -- wget -qO- -T 5 $POD_IP

# 5. NetworkPolicy
cat <<EOF | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-access
  namespace: calico-test
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

k -n calico-test run ok  --image=busybox:1.37 --rm -it --restart=Never -l access=true -- wget -qO- -T 5 web   # works
k -n calico-test run bad --image=busybox:1.37 --rm -it --restart=Never -- wget -qO- -T 5 web                 # times out
```

## Pitfalls

- Installing Calico with its default pool before checking the cluster's pod CIDR is easy to do. With a mismatch, pods on different nodes can't reach each other, and fixing it means reinstalling. Read `podSubnet` first.
- The operator needs a few seconds before `tigerastatus calico` even exists, and Calico takes 2-3 minutes after that. `k wait` fails right away on an object that doesn't exist yet.
