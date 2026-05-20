# Creating a Self-Managed Kubernetes Cluster on OCI Using CAPOCI and Cilium Native Pod Routing

This repository contains a minimal CAPOCI-based flow for creating a self-managed Kubernetes cluster on Oracle Cloud Infrastructure (OCI) and running Cilium with native pod routing.

A key recent OCI enhancement is the **FlexCIDR provider** that is shipped as part of the **OCI Cloud Controller Manager (CCM)**. It enables native pod routing for self-managed Kubernetes clusters by assigning worker-node `podCIDR`s from OCI subnet CIDR blocks so Cilium can run in native routing mode without an overlay.

## What this repo contains

- `cluster-template.yaml`: CAPOCI cluster template
- `cluster-create.sh`: example environment-variable-driven cluster generation script

## Architecture

The flow in this repo uses:

- **CAPOCI** to create the workload cluster
- **OCI CCM** with **FlexCIDR provider** to initialize nodes and assign worker `podCIDR`s
- **Cilium** with `routingMode=native` and `ipam.mode=kubernetes`
- **CoreDNS** running on worker nodes

The intended ownership model is:

- **Worker nodes**: get their `podCIDR`s from OCI FlexCIDR
- **Cilium**: consumes those worker `podCIDR`s in native routing mode

## Prerequisites

You need:

- an OCI tenancy and permissions to create compute and networking resources
- a VCN and subnets already created
- `clusterctl`
- `kubectl`
- `helm`
- access to a Kubernetes image in OCI for self-managed nodes
- an SSH public key
- CAPOCI management cluster already initialized

This repository assumes you are using [CAPOCI](https://github.com/oracle/cluster-api-provider-oci), Oracle's Cluster API Provider for OCI, to reconcile the Cluster API resources in this repository into OCI infrastructure. The manifests here are workload-cluster manifests, so they must be rendered and applied from a separate management cluster where CAPOCI is already installed.

For the management-cluster setup, follow Oracle's documented CAPOCI flow: choose a management cluster, prepare any custom OCI images, configure the required IAM, provision the management cluster, install the required tools, configure IAM for the self-provisioned workload cluster, [Install Cluster API Provider for Oracle Cloud Infrastructure](https://oracle.github.io/cluster-api-provider-oci/gs/install-cluster-api.html#install-cluster-api-provider-for-oracle-cloud-infrastructure), and then [Create Workload Cluster](https://oracle.github.io/cluster-api-provider-oci/gs/create-workload-cluster.html). If your management cluster runs in OCI, I recommend using instance principal for CAPOCI authentication. In that case, create a dynamic group for the management-cluster instances and grant the CAPOCI permissions described in the install guide, instead of using a user-group-based CAPOCI credential setup. The workload cluster still needs the self-provisioned IAM policies described in [Configure policies for a self-provisioned cluster](https://oracle.github.io/cluster-api-provider-oci/gs/iam/iam-self-provisioned.html#configure-policies-for-a-self-provisioned-cluster).

## Required OCI network infrastructure

Before CAPOCI creates the workload cluster, OCI networking must already exist. At minimum, you need one **VCN**, a subnet for the Kubernetes **control-plane endpoint**, a subnet referenced with the `control-plane` role, and a subnet referenced with the `worker` role in `OCICluster.networkSpec.vcn.subnets`. In this example the control-plane and worker nodes can share the same OCI node subnet, but they are still modeled as separate CAPOCI roles. That subnet must have route tables, security lists or NSGs, and gateways appropriate for your environment so nodes can reach the Kubernetes API, pull images, talk to OCI APIs, and communicate with each other. If the cluster needs outbound internet access, that usually means an **Internet Gateway** for public subnets or a **NAT Gateway** for private subnets; a **Service Gateway** is commonly used for private access to OCI services such as OCIR.

When you use Cilium in native routing mode together with OCI FlexCIDR, the OCI node subnet must also include the pod address space that will be assigned to worker nodes. I recommend allocating a dedicated worker Pod CIDR block and explicitly adding it to the OCI subnet as an additional IPv4 CIDR block. OCI documents that process here: [Adding an IPv4 CIDR block to a subnet](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/add-ipv4-cidr.htm). In short, your OCI subnet design must be ready to carry both node IPs and the worker pod IP ranges that the FlexCIDR provider will allocate.

## CIDR design

Use **non-overlapping** CIDR ranges.

Example:

- `OCI_MACHINE_POOL_CIDR_BLOCKS=10.0.100.0/22`

Important rules:

- worker FlexCIDR blocks must be valid CIDR blocks inside the OCI node subnet
- worker FlexCIDR blocks must not overlap with other address ranges already in use
- pod CIDRs used for native routing must be valid OCI-routable subnet space

In this example, the cluster uses a `MachinePool` together with `OCIMachinePool` in the CAPOCI template. Creating those Kubernetes objects causes CAPOCI to create the corresponding OCI **instance configuration** and **instance pool** for the worker nodes. The pod IP range available to each worker node is controlled through the `flexcidr-primary-vnic` metadata that is injected into the OCI instance configuration. In particular, `cidr-blocks` defines the worker pod CIDR pool and `ip-count` defines how many pod IPs a node can allocate. For example, if `cidr-blocks` is set to `10.0.100.0/22` and `ip-count` is `32`, the FlexCIDR logic allocates `/27`-sized worker node pod ranges, allowing each worker node to allocate 32 pod IPs. On provisioned worker nodes, this appears in OCI instance metadata in a form similar to `"metadata": { "flexcidr-primary-vnic": "{\"cidr-blocks\":[\"10.0.100.0/22\"],\"ip-count\":32}" }`. The OCI FlexCIDR provider reads this worker metadata from IMDS and assigns the corresponding `podCIDR` to the Kubernetes Node object.

## Template variables

Main variables used by `cluster-template.yaml`:

- `CLUSTER_NAME`
- `NAMESPACE`
- `COMPARTMENT_ID`
- `OCI_IMAGE_ID`
- `KUBERNETES_VERSION`
- `VCN_ID`
- `SUBNET_CONTROL_PLANE_ENDPOINT_ID`
- `SUBNET_CONTROL_PLANE_ID`
- `SUBNET_WORKER_ID`
- `OCI_MACHINE_POOL_CIDR_BLOCKS`
- `OCI_MACHINE_POOL_IP_COUNT`

## Generate the cluster manifest

Example:

```bash
COMPARTMENT_ID=<cluster-compartment-ocid> \
OCI_SSH_KEY="$(cat <path to SSH public key>)" \
KUBERNETES_VERSION=v1.34.3 \
OCI_IMAGE_ID=<image-ocid> \
CONTROL_PLANE_MACHINE_COUNT=1 \
NAMESPACE=default \
WORKER_MACHINE_COUNT=2 \
OCI_NODE_MACHINE_TYPE=VM.Standard.E5.Flex \
OCI_NODE_MACHINE_TYPE_OCPUS=2 \
OCI_NODE_MACHINE_TYPE_MEMORY_IN_GBS=32 \
OCI_MACHINE_POOL_CIDR_BLOCKS=10.0.100.0/22 \
OCI_MACHINE_POOL_IP_COUNT=32 \
VCN_ID=<vcn-ocid> \
SUBNET_CONTROL_PLANE_ENDPOINT_ID=<control-plane-endpoint-subnet-ocid> \
SUBNET_CONTROL_PLANE_ID=<control-plane-subnet-ocid> \
SUBNET_WORKER_ID=<worker-subnet-ocid> \
clusterctl generate cluster test --from cluster-template.yaml > rendered.yaml
```

Apply it:

```bash
kubectl apply -f rendered.yaml
```

Check that the cluster was successfully created:

```bash
kubectl get clusters -A
```

Example:

```text
NAMESPACE   NAME   CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE     VERSION
default     test                  False       1            0              1               0           0             0              Provisioned   4m44s
```

Check that the machine pool was successfully created:

```bash
kubectl get machinepools -A
```

Example:

```text
NAMESPACE   NAME         CLUSTER   DESIRED   CURRENT   READY   AVAILABLE   UP-TO-DATE   PHASE       AGE     VERSION
default     test-mp-0    test      2         2         0       0           2            ScalingUp   10m     v1.34.3
```

To download the kubeconfig for the created cluster, run `clusterctl get kubeconfig <cluster-name> -n <namespace>` and redirect it to a file. For example:

```bash
clusterctl get kubeconfig test -n default > ~/.kube/test.kubeconfig
export KUBECONFIG=~/.kube/test.kubeconfig
```

Check that the cluster nodes are being provisioned:

```bash
kubectl get nodes
```

Provisioning the control plane and worker nodes on OCI can take some time, so if the nodes do not appear immediately, wait and run the command again. After the nodes are provisioned on OCI and join the cluster, the node state is expected to be `NotReady`.

Example:

```text
NAME                        STATUS     ROLES           AGE     VERSION
inst-1vn9n-test-mp-0        NotReady   <none>          3m8s    v1.34.3
inst-momez-test-mp-0        NotReady   <none>          3m1s    v1.34.3
test-control-plane-lg2rd    NotReady   control-plane   6m37s   v1.34.3
```

## Install OCI CCM first

The nodes are configured with `cloud-provider: external`, so OCI CCM must be installed before the cluster becomes fully initialized.

Note: OCI FlexCIDR provider was included in OCI CCM `v1.33.1-rc3`. It is expected to be merged into a regular OCI CCM release in the future, but at the time of writing you need to use the release-candidate image from `ghcr.io/akarshes/cloud-provider-oci-amd64:v1.33.1-rc3`.

Download the upstream OCI CCM provider-config template and save it locally as `cloud-provider.yaml`:

```bash
curl -L https://raw.githubusercontent.com/oracle/oci-cloud-controller-manager/master/manifests/provider-config-example.yaml -o cloud-provider.yaml
```

Then update `cloud-provider.yaml` for your environment. For this guide, set `useInstancePrincipals: true` and customize the OCIDs for `compartment`, `vcn`, `loadBalancer.subnet1`, and `loadBalancer.subnet2`. If you are explicitly managing security lists through the OCI CCM config, also populate the `securityLists` mapping with your subnet and security list OCIDs.

Create the OCI CCM secret first:

```bash
kubectl create secret generic oci-cloud-controller-manager \
  -n kube-system \
  --from-file=cloud-provider.yaml
```

Then install OCI CCM.

Download the manifests from the upstream repository:

```bash
curl -L https://raw.githubusercontent.com/oracle/oci-cloud-controller-manager/master/manifests/cloud-controller-manager/oci-cloud-controller-manager.yaml -o oci-cloud-controller-manager.yaml
curl -L https://raw.githubusercontent.com/oracle/oci-cloud-controller-manager/master/manifests/cloud-controller-manager/oci-cloud-controller-manager-rbac.yaml -o oci-cloud-controller-manager-rbac.yaml
```

Update the controller image in `oci-cloud-controller-manager.yaml`:

```yaml
image: ghcr.io/akarshes/cloud-provider-oci-amd64:v1.33.1-rc3
```

Enable the FlexCIDR provider in the OCI CCM configuration. In `oci-cloud-controller-manager.yaml`, set:

```yaml
env:
  - name: ENABLE_FLEX_CIDR_CONTROLLER
    value: "true"
```

Before applying `oci-cloud-controller-manager.yaml`, add a toleration so the controller can be scheduled on the control-plane node while it is still `NotReady`:

```yaml
tolerations:
  - key: node.kubernetes.io/not-ready
    operator: Exists
    effect: NoSchedule
```

Then apply the manifests:

```bash
kubectl apply -f oci-cloud-controller-manager-rbac.yaml
kubectl apply -f oci-cloud-controller-manager.yaml
```

OCI recommends using Instance Principal authentication for CCM. For standard CCM operation, the worker-node compartment policy must allow `use virtual-network-family`. To use the FlexCIDR provider, that permission must be elevated to `manage virtual-network-family` in the worker-node compartment, because the controller needs to assign and manage pod IPs on the worker node VNICs.

Verify:

```bash
kubectl -n kube-system get ds,pods | grep -i oci-cloud-controller-manager
kubectl get nodes -o wide
```

Example:

```text
daemonset.apps/oci-cloud-controller-manager   1         1         1       1            1           node-role.kubernetes.io/control-plane=   14m
pod/oci-cloud-controller-manager-9rsln                  1/1     Running   0          105s

NAME                        STATUS     ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
inst-1vn9n-test-mp-0        NotReady   <none>          28m   v1.34.3   10.0.52.141   <none>        Ubuntu 22.04.5 LTS   6.8.0-1047-oracle   containerd://1.7.29
inst-momez-test-mp-0        NotReady   <none>          28m   v1.34.3   10.0.61.14    <none>        Ubuntu 22.04.5 LTS   6.8.0-1047-oracle   containerd://1.7.29
test-control-plane-lg2rd    NotReady   control-plane   31m   v1.34.3   10.0.42.72    <none>        Ubuntu 22.04.5 LTS   6.8.0-1047-oracle   containerd://1.7.29
```

Verify that worker nodes receive `podCIDR`s:

```bash
kubectl get nodes -l cilium-node=true -o jsonpath='{range .items[*]}{.metadata.name}{"  podCIDR="}{.spec.podCIDR}{"\n"}{end}'
```

Workers must get non-overlapping slices from `OCI_MACHINE_POOL_CIDR_BLOCKS`, for example:

```text
inst-1vn9n-test-mp-0  podCIDR=10.0.103.128/27
inst-momez-test-mp-0  podCIDR=10.0.102.224/27
```

If `podCIDR`s are not assigned to worker nodes, check the OCI CCM logs:

```bash
kubectl -n kube-system logs ds/oci-cloud-controller-manager
```

For every worker node, the OCI CCM log should show that the node was successfully patched with a `podCIDR` from the associated FlexCIDR pool, for example:

```text
2026-05-19T20:32:14.209Z  INFO  flexcidr/flexcidr.go:227  PrimaryVnicConfig CIDR blocks: [10.0.100.0/22]  {"component": "cloud-controller-manager", "node": "inst-1vn9n-test-mp-0"}
2026-05-19T20:32:14.791Z  INFO  flexcidr/flexcidr.go:117  successfully patched node inst-1vn9n-test-mp-0 podCIDRs to [10.0.103.128/27]   {"component": "cloud-controller-manager", "node": "inst-1vn9n-test-mp-0"}
```

## Install Cilium third

Install Cilium only after worker `podCIDR`s are assigned.

In this example, Cilium is installed only on worker nodes, using the label `cilium-node=true`. That means the Cilium agent, Cilium Envoy, and the Cilium operator are all scheduled only on nodes with that label.

The worker nodes are already labeled by `cluster-template.yaml`. You can verify that with:

```bash
kubectl get nodes --show-labels
```

This example uses an OCI VCN with CIDR `10.0.0.0/16`, so the Cilium native-routing settings below use that VCN range for `ipv4NativeRoutingCIDR` and `ipMasqAgent.nonMasqueradeCIDRs`.

Recommended settings when installing Cilium:

- `routingMode=native`
- `ipam.mode=kubernetes`
- `enableEndpointRoutes=true`
- `ipv4NativeRoutingCIDR=10.0.0.0/16`

Install Cilium with worker-only selectors:

```bash
helm upgrade --install cilium cilium/cilium --version 1.19.1 \
  -n kube-system \
  --create-namespace \
  --set routingMode=native \
  --set ipam.mode=kubernetes \
  --set enableEndpointRoutes=true \
  --set kubeProxyReplacement=false \
  --set ipv4.enabled=true \
  --set enableIPv4=true \
  --set enableIPv4Masquerade=true \
  --set ipMasqAgent.enabled=true \
  --set ipv6.enabled=false \
  --set enableIPv6=false \
  --set enableIPv6Masquerade=false \
  --set bpf.masquerade=true \
  --set ipv4NativeRoutingCIDR=10.0.0.0/16 \
  --set nodePort.enabled=true \
  --set ipMasqAgent.nonMasqueradeCIDRs='{10.0.0.0/16}' \
  --set ipMasqAgent.masqLinkLocal=false \
  --set-string 'nodeSelector.cilium-node'='true' \
  --set-string 'envoy.nodeSelector.cilium-node'='true' \
  --set-string 'operator.nodeSelector.cilium-node'='true'
```

## Verify the cluster

Check nodes:

```bash
kubectl get nodes
kubectl describe nodes | egrep -i 'Name:|Taints:'
kubectl get nodes -l cilium-node=true -o jsonpath='{range .items[*]}{.metadata.name}{"  podCIDR="}{.spec.podCIDR}{"\n"}{end}'
```

Check Cilium:

```bash
kubectl -n kube-system get pods -o wide | grep cilium
kubectl -n kube-system exec ds/cilium -- cilium status
kubectl -n kube-system exec ds/cilium -- cilium-health status
```

Check CoreDNS:

```bash
kubectl -n kube-system get pods -o wide | grep coredns
```

## Summary

The critical part of this design is separating responsibilities:

- **OCI CCM** initializes nodes
- **OCI FlexCIDR provider** assigns worker `podCIDR`s
- **Cilium** consumes those worker `podCIDR`s in native routing mode
- **CoreDNS and workloads** run on worker nodes
