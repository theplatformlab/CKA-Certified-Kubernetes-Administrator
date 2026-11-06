# Exercise Testing Checklist

YAML validation catches malformed manifests. It does not show that an exercise can be followed, that its checks prove the requested result, or that cleanup works. Use this checklist when adding or changing an exercise.

## 1. Check the Exercise Instructions

- [ ] Setup says what cluster resources and add-ons are required.
- [ ] Setup commands work in order from a fresh cluster, or list any prerequisites that cannot be created there.
- [ ] Tasks describe the requested end state without giving away the solution.
- [ ] Verification checks the actual requirements, not only that a resource exists.
- [ ] Cleanup removes resources created by the exercise and does not remove shared or pre-existing resources.
- [ ] Any step requiring multiple nodes, a special CNI, a storage provisioner, host access, or control-plane changes is called out.

Use the same short block near the top of an exercise so students can decide whether their lab is suitable:

```markdown
## Lab Requirements

- Cluster: single-node kind or Minikube / multi-node kubeadm VMs
- Components: list required CNI, storage provisioner, or other add-ons; write `None` if there are none
- Access: kubectl namespace permissions / node SSH and sudo
- Test record: date, Kubernetes version, cluster type, and result; write `Not tested` until it has actually been run
```

Keep only the applicable choices in each exercise. Do not copy the example alternatives as if all are required.

## 2. Use a Disposable Cluster

Never test node, networking, storage, or control-plane changes against a production or shared cluster. Both the kind bootstrap script and Minikube switch the current kubectl context. Use a new, unused cluster/profile name, and do not pass `--recreate` unless you have confirmed the named kind cluster is disposable.

For kind, Windows users should run the script from WSL2 Ubuntu with Docker Desktop's WSL integration enabled. For a no-Docker Windows setup, use Minikube with VirtualBox on Windows Home or Hyper-V on a supported Windows edition; see the [README setup instructions](README.md#no-docker-use-minikube-with-a-vm-driver). Run repository Bash aliases from Git Bash or WSL after confirming both shells point to the same kubeconfig.

From the repository root, create a fresh local cluster:

```bash
CLUSTER_NAME=cka-check-01 bash scripts/init-cluster.sh
```

The kind script uses the repository's default Kubernetes version unless `KUBE_VERSION` is set. Confirm that kubectl is pointed at the cluster you just created before applying anything:

```bash
kubectl config current-context
kubectl get nodes -o wide
kubectl version
```

The context should be `kind-cka-check-01`. If it is not, stop and select the disposable context explicitly:

```bash
kubectl config use-context kind-cka-check-01
```

Load the repository aliases if the exercise uses them:

```bash
source scripts/exam-setup.sh
```

## 3. Run the Exercise

- [ ] Start with the exercise's Setup section; don't manually create extra resources to make a broken setup appear to work.
- [ ] Wait for required Pods and controllers to become Ready before attempting the task.
- [ ] Follow the Tasks section without opening the solution.
- [ ] Run every Verify command and check that its expected result is clear.
- [ ] Try the cleanup commands and confirm exercise-owned resources are gone.
- [ ] If the exercise has an optional challenge, restore any changed settings before cleanup.

For a troubleshooting exercise, confirm setup creates the stated failure and that the verification passes after the learner fixes it. For a build exercise, confirm verification fails or is incomplete before the task and passes afterward.

## 4. Record the Result

For each test, record:

- Exercise number and date
- Kubernetes version and cluster type
- Required add-ons or special topology
- Whether setup completed from a clean cluster
- Any task step that was ambiguous or impossible
- Verification command and observed result
- Whether cleanup completed

If kind or Minikube cannot test a requirement, say exactly what was not tested and why. Use a disposable multi-VM kubeadm lab for exercises that require node failures, control-plane changes, or multi-node networking. Do not mark an exercise as clean-cluster tested based only on YAML lint or a successful `kubectl apply`.

For Minikube on Windows Home, use a unique profile and the VirtualBox driver:

```bash
minikube start -p cka-check-01 --driver=virtualbox --kubernetes-version=v1.35.1
kubectl config current-context
kubectl get nodes -o wide
```

For Windows editions with Hyper-V, macOS, and Linux, use the matching Minikube driver command in the [README setup instructions](README.md#no-docker-use-minikube-with-a-vm-driver). Do not continue until the context and node output identify the disposable test cluster.

## 5. Reset the Test Environment

After confirming the exercise cleanup, delete only the disposable cluster you created:

```bash
kind delete cluster --name cka-check-01
```

This deletes that kind cluster and its data. It does not reset or clean any other cluster. Keep the name consistent with the fresh cluster created above.

If you created the Minikube profile instead, delete only that profile:

```bash
minikube delete -p cka-check-01
```
