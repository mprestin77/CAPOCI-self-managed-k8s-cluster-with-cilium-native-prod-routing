# Creating a Self-Managed Kubernetes Cluster on OCI Using CAPOCI and Cilium Native Pod Routing

This repository contains a minimal CAPOCI-based flow for creating a self-managed Kubernetes cluster on Oracle Cloud Infrastructure (OCI) and running Cilium with native pod routing.

A key recent OCI enhancement is the **FlexCIDR provider** that is shipped as part of the **OCI Cloud Controller Manager (CCM)**. It enables native pod routing for self-managed Kubernetes clusters by assigning node `podCIDR`s from OCI subnet CIDR blocks so Cilium can run in native routing mode without an overlay.

## What this repo contains

- `cluster-template.yaml`: CAPOCI cluster template
- `cluster-create.sh`: example environment-variable-driven cluster generation script

## Architecture

The flow in this repo uses:

- **CAPOCI** to create the workload cluster
- **OCI CCM** with **FlexCIDR provider** to initialize nodes and assign node `podCIDR`s
- **Cilium** with `routingMode=native` and `ipam.mode=kubernetes`

The intended ownership model is:

- **Control-plane and worker nodes**: get their `podCIDR`s from OCI FlexCIDR
- **Cilium**: consumes those node `podCIDR`s in native routing mode

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

For the management-cluster setup:

1. [Build a custom image](https://oracle.github.io/cluster-api-provider-oci/gs/custom-machine-images.html). CAPOCI uses custom OCI machine images to create the workload-cluster control-plane and worker nodes. The image must contain the Kubernetes components required for self-managed nodes, and the `OCI_IMAGE_ID` variable in this repo points to that image.
2. [Configure IAM policies required for the management cluster](https://oracle.github.io/cluster-api-provider-oci/gs/iam/iam-self-provisioned.html). The management cluster is the Kubernetes cluster where Cluster API and CAPOCI run. CAPOCI watches the Cluster API resources created in that cluster and reconciles them into OCI compute, networking, and load balancer resources. If you plan to run the management cluster in OCI, I recommend using instance principal with a dynamic group. In that case, create a dynamic group for the management-cluster instances and grant the CAPOCI permissions described in the install guide, instead of using a user-group-based CAPOCI credential setup.
3. [Provision a management cluster](https://oracle.github.io/cluster-api-provider-oci/gs/mgmt/mgmt-kind.html). You can use a Kind cluster, OKE, or another compliant Kubernetes cluster as the management cluster. Its role is to host the Cluster API CRDs, the CAPOCI controllers, and the kubeconfig context from which you create and manage workload clusters.
4. [Install CAPOCI and initialize the management cluster](https://oracle.github.io/cluster-api-provider-oci/gs/install-cluster-api.html). This step installs the Cluster API and CAPOCI components into the management cluster so it can understand CAPOCI resource types and reconcile workload-cluster manifests into OCI infrastructure. If the management cluster runs in OCI, I recommend using instance principal authentication for CAPOCI.

The workload cluster still needs the self-provisioned IAM policies described in [Configure policies for a self-provisioned cluster](https://oracle.github.io/cluster-api-provider-oci/gs/iam/iam-self-provisioned.html#configure-policies-for-a-self-provisioned-cluster). If you use instance principal for workload-cluster components, grant the equivalent policies to the appropriate dynamic group.

## Required OCI network infrastructure

Before CAPOCI creates the workload cluster, OCI networking must already exist. At minimum, you need one **VCN**, a subnet for the Kubernetes **control-plane endpoint**, a subnet referenced with the `control-plane` role, and a subnet referenced with the `worker` role in `OCICluster.networkSpec.vcn.subnets`. In this example the control-plane and worker nodes can share the same OCI node subnet, but they are still modeled as separate CAPOCI roles. That subnet must have route tables, security lists or NSGs, and gateways appropriate for your environment so nodes can reach the Kubernetes API, pull images, talk to OCI APIs, and communicate with each other. If the cluster needs outbound internet access, that usually means an **Internet Gateway** for public subnets or a **NAT Gateway** for private subnets; a **Service Gateway** is commonly used for private access to OCI services such as OCIR.

In OCI security lists or NSGs, make sure the Kubernetes ports and protocols required between the control-plane nodes, worker nodes, and the API endpoint are allowed. Refer to the Kubernetes [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) reference when defining the OCI network rules.

When you use Cilium in native routing mode together with OCI FlexCIDR, the OCI node subnet must also include the pod address space that will be assigned to cluster nodes. I recommend allocating a dedicated node Pod CIDR block and explicitly adding it to the OCI subnet as an additional IPv4 CIDR block. OCI documents that process here: [Adding an IPv4 CIDR block to a subnet](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/add-ipv4-cidr.htm). In short, your OCI subnet design must be ready to carry both node IPs and the node pod IP ranges that the FlexCIDR provider will allocate.

## CIDR design

Use **non-overlapping** CIDR ranges when control-plane and worker nodes use different FlexCIDR pools. If both roles use the same FlexCIDR pool, the assigned node `podCIDR`s must still be non-overlapping.

Example:

- `OCI_CONTROL_PLANE_CIDR_BLOCKS=10.0.100.0/22`
- `OCI_CONTROL_PLANE_IP_COUNT=16`
- `OCI_MACHINE_POOL_CIDR_BLOCKS=10.0.100.0/22`
- `OCI_MACHINE_POOL_IP_COUNT=32`

Important rules:

- FlexCIDR blocks must be valid CIDR blocks inside the OCI node subnet
- FlexCIDR blocks must not overlap with other address ranges already in use
- pod CIDRs used for native routing must be valid OCI-routable subnet space

In this example, the cluster uses a `MachinePool` together with `OCIMachinePool` for the worker nodes and an `OCIMachineTemplate` for the control plane. The pod IP range available to each node is controlled through the `flexcidr-primary-vnic` metadata. For the worker nodes, that metadata is injected through `OCIMachinePool.spec.instanceConfiguration.metadata`. For the control-plane nodes, the same metadata is injected through `OCIMachineTemplate.spec.template.spec.metadata`, so CAPOCI provisions both roles with the required FlexCIDR configuration from the start. The control plane and worker nodes can use different FlexCIDR settings. In particular, `cidr-blocks` defines the node pod CIDR pool and `ip-count` defines how many pod IPs a node can allocate. For example, if control-plane nodes use `cidr-blocks=10.0.100.0/22` with `ip-count=16`, FlexCIDR allocates `/28`-sized pod ranges for control-plane nodes. If worker nodes use `cidr-blocks=10.0.100.0/22` with `ip-count=32`, FlexCIDR allocates `/27`-sized pod ranges for worker nodes. In OCI instance metadata, this appears in a form similar to `"metadata": { "flexcidr-primary-vnic": "{\"cidr-blocks\":[\"10.0.100.0/22\"],\"ip-count\":16}" }` for a control-plane node. The OCI FlexCIDR provider reads this metadata from IMDS and assigns the corresponding `podCIDR` to the Kubernetes Node object.

## Template variables

Variables used by `cluster-template.yaml`:

- `CLUSTER_NAME`
- `NAMESPACE`
- `COMPARTMENT_ID`
- `OCI_SSH_KEY`
- `OCI_IMAGE_ID`
- `KUBERNETES_VERSION`
- `SERVICE_DOMAIN`
- `CONTROL_PLANE_MACHINE_COUNT`
- `OCI_CONTROL_PLANE_MACHINE_TYPE`
- `OCI_CONTROL_PLANE_MACHINE_TYPE_OCPUS`
- `OCI_CONTROL_PLANE_CIDR_BLOCKS`
- `OCI_CONTROL_PLANE_IP_COUNT`
- `OCI_CONTROL_PLANE_PV_TRANSIT_ENCRYPTION`
- `WORKER_MACHINE_COUNT`
- `OCI_NODE_MACHINE_TYPE`
- `OCI_NODE_MACHINE_TYPE_OCPUS`
- `OCI_NODE_MACHINE_TYPE_MEMORY_IN_GBS`
- `VCN_ID`
- `SUBNET_CONTROL_PLANE_ENDPOINT_ID`
- `SUBNET_CONTROL_PLANE_ID`
- `SUBNET_WORKER_ID`
- `OCI_MACHINE_POOL_CIDR_BLOCKS`
- `OCI_MACHINE_POOL_IP_COUNT`

## Generate the cluster manifest

Example:

```bash
export CLUSTER_NAME=test
export NAMESPACE=default
export COMPARTMENT_ID="<cluster-compartment-ocid>"
export OCI_SSH_KEY=$(cat <path to SSH public key>)
export OCI_IMAGE_ID="<image-ocid>"
export KUBERNETES_VERSION=v1.35.2
export SERVICE_DOMAIN=cluster.local
export CONTROL_PLANE_MACHINE_COUNT=1
export OCI_CONTROL_PLANE_MACHINE_TYPE="VM.Standard.E5.Flex"
export OCI_CONTROL_PLANE_MACHINE_TYPE_OCPUS=1
export OCI_CONTROL_PLANE_CIDR_BLOCKS="10.0.100.0/22"
export OCI_CONTROL_PLANE_IP_COUNT=16
export OCI_CONTROL_PLANE_PV_TRANSIT_ENCRYPTION=true
export WORKER_MACHINE_COUNT=2
export OCI_NODE_MACHINE_TYPE="VM.Standard.E5.Flex"
export OCI_NODE_MACHINE_TYPE_OCPUS=2
export OCI_NODE_MACHINE_TYPE_MEMORY_IN_GBS=32
export VCN_ID="<vcn-ocid>"
export SUBNET_CONTROL_PLANE_ENDPOINT_ID="<control-plane-endpoint-subnet-ocid>"
export SUBNET_CONTROL_PLANE_ID="<control-plane-subnet-ocid>"
export SUBNET_WORKER_ID="<worker-subnet-ocid>"
export OCI_MACHINE_POOL_CIDR_BLOCKS="10.0.100.0/22"
export OCI_MACHINE_POOL_IP_COUNT=32

clusterctl generate cluster "${CLUSTER_NAME}" \
--from cluster-template.yaml > rendered.yaml
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
default     test-mp-0    test      2         2         0       0           2            ScalingUp   10m     v1.35.2
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
inst-gdtie-test-mp-0       NotReady   <none>          4m50s   v1.35.2
inst-j1f4r-test-mp-0       NotReady   <none>          4m48s   v1.35.2
test-control-plane-wbrx9   NotReady   control-plane   8m24s   v1.35.2
```

## Install OCI CCM

The nodes are configured with `cloud-provider: external`, so OCI CCM must be installed before the cluster becomes fully initialized.

Note: OCI FlexCIDR provider was included in OCI CCM `v1.33.1-rc3`. It is expected to be merged into a regular OCI CCM release in the future, but at the time of writing you need to use the release-candidate image from `ghcr.io/akarshes/cloud-provider-oci-amd64:v1.33.1-rc3`.

The `cluster-template.yaml` in this repo already sets `flexcidr-primary-vnic` for both worker and control-plane nodes, so no separate instance-metadata update is needed before installing OCI CCM. Make sure `OCI_CONTROL_PLANE_CIDR_BLOCKS`, `OCI_CONTROL_PLANE_IP_COUNT`, `OCI_MACHINE_POOL_CIDR_BLOCKS`, and `OCI_MACHINE_POOL_IP_COUNT` are set correctly before you generate and apply `rendered.yaml`.

Download the upstream OCI CCM provider-config template and save it locally as `cloud-provider.yaml`:

```bash
export RELEASE=v1.35.0

curl -L https://raw.githubusercontent.com/oracle/oci-cloud-controller-manager/${RELEASE}/manifests/provider-config-example.yaml -o provider-config.yaml
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
curl -L https://raw.githubusercontent.com/oracle/oci-cloud-controller-manager/${RELEASE}/manifests/cloud-controller-manager/oci-cloud-controller-manager.yaml -o oci-cloud-controller-manager.yaml
curl -L https://raw.githubusercontent.com/oracle/oci-cloud-controller-manager/${RELEASE}/manifests/cloud-controller-manager/oci-cloud-controller-manager-rbac.yaml -o oci-cloud-controller-manager-rbac.yaml
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

OCI recommends using Instance Principal authentication for CCM. For standard CCM operation, the cluster-node compartment policy must allow `use virtual-network-family`. To use the FlexCIDR provider, that permission must be elevated to `manage virtual-network-family` in the cluster-node compartment, because the controller needs to assign and manage pod IPs on the node VNICs.

Verify:

```bash
kubectl -n kube-system get ds,pods | grep -i oci-cloud-controller-manager
kubectl get nodes -o wide
```

Example:

```text
daemonset.apps/oci-cloud-controller-manager   1         1         1       1            1           node-role.kubernetes.io/control-plane=   14m
pod/oci-cloud-controller-manager-9rsln                  1/1     Running   0          105s

NAME                       STATUS     ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
inst-gdtie-test-mp-0       NotReady   <none>          4h14m   v1.35.2   10.0.49.204   <none>        Ubuntu 22.04.5 LTS   6.8.0-1060-oracle   containerd://1.7.29
inst-j1f4r-test-mp-0       NotReady   <none>          4h14m   v1.35.2   10.0.44.45    <none>        Ubuntu 22.04.5 LTS   6.8.0-1060-oracle   containerd://1.7.29
test-control-plane-hgrpx   NotReady   control-plane   52m     v1.35.2   10.0.34.146   <none>        Ubuntu 22.04.5 LTS   6.8.0-1060-oracle   containerd://1.7.29
```

Verify that all nodes receive `podCIDR`s:

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"  podCIDR="}{.spec.podCIDR}{"\n"}{end}'
```

All nodes must get non-overlapping slices from the configured FlexCIDR blocks, for example:

```text
inst-gdtie-test-mp-0  podCIDR=10.0.100.192/27
inst-j1f4r-test-mp-0  podCIDR=10.0.101.64/27
test-control-plane-hgrpx  podCIDR=10.0.101.208/28
```

If `podCIDR`s are not assigned to the nodes, check the OCI CCM logs:

```bash
kubectl -n kube-system logs ds/oci-cloud-controller-manager
```

For each node, look for log lines showing that the node was successfully patched with a `podCIDR` from the associated FlexCIDR pool, for example:

```text
2026-05-20T17:24:50.300Z  INFO	flexcidr/flexcidr.go:117  successfully patched node inst-1vn9n-test-mp-0 podCIDRs to [10.0.103.128/27]	{"component": "cloud-controller-manager", "node": "inst-1vn9n-test-mp-0"}
2026-05-20T17:24:51.466Z  INFO	flexcidr/flexcidr.go:117  successfully patched node inst-momez-test-mp-0 podCIDRs to [10.0.102.224/27]	{"component": "cloud-controller-manager", "node": "inst-momez-test-mp-0"}
2026-05-20T17:24:52.440   INFO	flexcidr/flexcidr.go:117  successfully patched node test-control-plane-lg2rd podCIDRs to [10.0.101.96/28]  {"component": "cloud-controller-manager", "node": "test-control-plane-lg2rd"}
```

If a node was not patched successfully, inspect the associated errors in the OCI CCM log for that node.

## Install Cilium

Install Cilium only after node `podCIDR`s are assigned. To find the latest Cilium release, see [Cilium releases](https://github.com/cilium/cilium/releases). To verify Kubernetes compatibility, check the [requirements page for that Cilium major/minor version] (https://docs.cilium.io/en/v<major.minor>/network/kubernetes/requirements/)

In this example, Cilium is installed on all nodes, including the control plane, so the CNI is initialized everywhere. CoreDNS and regular workloads can still remain on worker nodes because the control-plane taint is unchanged.

This example uses an OCI VCN with CIDR `10.0.0.0/16`, so the Cilium native-routing settings below use that VCN range for `ipv4NativeRoutingCIDR` and `ipMasqAgent.nonMasqueradeCIDRs`.

Recommended settings when installing Cilium:

- `routingMode=native`
- `ipam.mode=kubernetes`
- `enableEndpointRoutes=true`
- `ipv4NativeRoutingCIDR=10.0.0.0/16`

Install Cilium:

```bash
helm upgrade --install cilium cilium/cilium --version 1.20.1 \
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
  --set ipMasqAgent.masqLinkLocal=false
```

## Verify the cluster

Check Cilium:

```bash
kubectl -n kube-system get pods -o wide | grep cilium
kubectl -n kube-system exec ds/cilium -- cilium status
kubectl -n kube-system exec ds/cilium -- cilium-health status
```

After Cilium pods are started on the control-plane and worker nodes, all nodes must be in `Ready` state.

Check nodes:

```bash
kubectl get nodes -o wide
```

Example:

```text
NAME                       STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
inst-gdtie-test-mp-0       Ready    <none>          20h   v1.35.2   10.0.49.204   <none>        Ubuntu 22.04.5 LTS   6.8.0-1060-oracle   containerd://1.7.29
inst-j1f4r-test-mp-0       Ready    <none>          20h   v1.35.2   10.0.44.45    <none>        Ubuntu 22.04.5 LTS   6.8.0-1060-oracle   containerd://1.7.29
test-control-plane-hgrpx   Ready    control-plane   17h   v1.35.2   10.0.34.146   <none>        Ubuntu 22.04.5 LTS   6.8.0-1060-oracle   containerd://1.7.29
```

Check CoreDNS:

```bash
kubectl -n kube-system get pods -o wide | grep coredns
```

Example:

```text
coredns-7d764666f9-j84pl                           1/1     Running   0          20h    10.0.101.215   test-control-plane-hgrpx   <none>           <none>
coredns-7d764666f9-tjrj5                           1/1     Running   0          20h    10.0.101.222   test-control-plane-hgrpx   <none>           <none>
```

## Summary

The critical part of this design is separating responsibilities:

- **OCI CCM** initializes nodes
- **OCI FlexCIDR provider** assigns node `podCIDR`s
- **Cilium** consumes those node `podCIDR`s in native routing mode
