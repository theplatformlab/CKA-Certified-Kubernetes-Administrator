# Move new Services to another IP range

**Context:** `kubectl config use-context {{CONTEXT}}`

The Service IP range of cluster `{{CLUSTER}}` clashes with a network the company wants to route. New Services have to get their ClusterIPs from `{{NEW_RANGE}}` from now on; Services that already exist keep their IPs. The control plane runs on `{{NODE_CP}}` (`ssh {{NODE_CP}}`).

1. In namespace `freight`, create a pod `tracker` with image `nginx:1.28` and a ClusterIP Service `tracker-legacy` that exposes it on port `80`. It gets an IP from the current range.
2. Change the Service IP range of the cluster to `{{NEW_RANGE}}`:
   - set `--service-cluster-ip-range` of kube-apiserver and kube-controller-manager to `{{NEW_RANGE}}`
   - make sure new Services can only get IPs from `{{NEW_RANGE}}`, while `tracker-legacy`, `kube-dns` and the other existing Services keep working with their current IPs
3. Create a second ClusterIP Service `tracker` for pod `tracker` on port `80`. Its ClusterIP must be in `{{NEW_RANGE}}`.

## Hints

- Since v1.33 Service IPs are allocated from `ServiceCIDR` objects (`k get servicecidr`). The API server creates the default one, `kubernetes`, from its flag only when it doesn't exist yet.
- After the flag change, look at the events of ServiceCIDR `kubernetes` (`k describe servicecidr kubernetes`). New ranges are added with another ServiceCIDR object, and IPs are drawn from every ServiceCIDR that is Ready.
- Create a ServiceCIDR for `{{NEW_RANGE}}`, then delete ServiceCIDR `kubernetes`. A finalizer keeps it while Services use its IPs, but a ServiceCIDR that is being deleted hands out no new IPs.

## Solution

```bash
k config use-context {{CONTEXT}}
k -n freight run tracker --image=nginx:1.28
k -n freight expose pod tracker --name=tracker-legacy --port=80
k -n freight get svc tracker-legacy                # 10.96.x.x
k get servicecidr                                  # kubernetes   10.96.0.0/16

ssh {{NODE_CP}}
cd /etc/kubernetes/manifests
grep service-cluster-ip-range kube-apiserver.yaml kube-controller-manager.yaml
sed -i 's|--service-cluster-ip-range=.*|--service-cluster-ip-range={{NEW_RANGE}}|' \
  kube-apiserver.yaml kube-controller-manager.yaml
watch crictl ps --name 'kube-apiserver|kube-controller-manager'   # both restart
exit

k get servicecidr                                  # still kubernetes   10.96.0.0/16
k describe servicecidr kubernetes
# Warning  KubernetesDefaultServiceCIDRInconsistent  The default ServiceCIDR [10.96.0.0/16]
#          does not match the controller flag configurations [{{NEW_RANGE}}]

cat <<YAML | k apply -f -
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata:
  name: freight-range
spec:
  cidrs:
  - {{NEW_RANGE}}
YAML
k delete servicecidr kubernetes --wait=false
k get servicecidr kubernetes -o jsonpath='{.status.conditions[0].reason}'   # Terminating

k -n freight expose pod tracker --name=tracker --port=80
k -n freight get svc                               # tracker-legacy 10.96.x.x, tracker in {{NEW_RANGE}}
```

Since the ServiceCIDR API (GA in v1.33), `--service-cluster-ip-range` only seeds the default ServiceCIDR `kubernetes` when the API server starts and finds none. Changing the flag on a running cluster changes nothing by itself: the API server keeps allocating from the existing object and only reports the mismatch as an event. A second ServiceCIDR extends the pool, and new IPs come from any Ready ServiceCIDR, so `tracker` could land in either range. Deleting `kubernetes` takes the old range out of service: its finalizer keeps it (condition `Terminating`) as long as `kubernetes.default`, `kube-dns` and `tracker-legacy` hold IPs from it, so they keep working, but no new IPs come from it. The flags still matter: once the old ServiceCIDR is gone, the API server recreates `kubernetes` from its flag, now with the new range (the controller manager's flag should agree with it). The full migration in the Kubernetes docs ("Reconfigure Default Service IP Ranges") also recreates the existing Services, including `kube-dns` and the kubelets' `clusterDNS`; that is out of scope here.
