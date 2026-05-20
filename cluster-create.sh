export CLUSTER_NAME="test"
export NAMESPACE="default"
export COMPARTMENT_ID="<compartment-ocid>"
export OCI_SSH_KEY=$(cat <path to SSH public key>)
export OCI_IMAGE_ID="<image-ocid>"
export KUBERNETES_VERSION="<Kubernetes version>" # Example: v1.34.3
export SERVICE_DOMAIN="cluster.local"
export CONTROL_PLANE_MACHINE_COUNT=<number of control plane nodes>
export OCI_CONTROL_PLANE_MACHINE_TYPE="VM.Standard.E5.Flex"
export OCI_CONTROL_PLANE_MACHINE_TYPE_OCPUS=1
export OCI_CONTROL_PLANE_CIDR_BLOCKS="<control-plane-cidr>" # Example: 10.0.100.0/22
export OCI_CONTROL_PLANE_IP_COUNT=<number of pod IPs per control plane node> # Example: 16
export OCI_CONTROL_PLANE_PV_TRANSIT_ENCRYPTION=true
export WORKER_MACHINE_COUNT=<number of worker nodes>
export OCI_NODE_MACHINE_TYPE="<OCI compute shape>" # Example: VM.Standard.E5.Flex
export OCI_NODE_MACHINE_TYPE_OCPUS=<number of OCPU per worker node>
export OCI_NODE_MACHINE_TYPE_MEMORY_IN_GBS=<memory in GB per worker node>
export VCN_ID="<vcn-ocid>"
export SUBNET_CONTROL_PLANE_ENDPOINT_ID="<control-plane-endpoint-subnet-ocid>"
export SUBNET_CONTROL_PLANE_ID="<control-plane-subnet-ocid>"
export SUBNET_WORKER_ID="<worker-subnet-ocid>"
export OCI_MACHINE_POOL_CIDR_BLOCKS="<machine-pool-cidr>" # Example: 10.0.100.0/22
export OCI_MACHINE_POOL_IP_COUNT=<number of pod IPs per worker node> # Example: 32

clusterctl generate cluster "${CLUSTER_NAME}" \
--from cluster-template.yaml > rendered.yaml
