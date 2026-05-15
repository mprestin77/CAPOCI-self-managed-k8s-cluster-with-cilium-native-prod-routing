export COMPUTE_COMPARTMENT_ID="<compute-compartment-ocid>"
export NETWORK_COMPARTMENT_ID="<network-compartment-ocid>"
export OCI_SSH_KEY=$(cat <path to SSH public key>)
export KUBERNETES_VERSION=<Kubernetes version> # Example: v1.34.3
export OCI_IMAGE_ID="<image-ocid>"
export CONTROL_PLANE_MACHINE_COUNT=<number of control plane nodes>
export NAMESPACE=default
export WORKER_MACHINE_COUNT=<number of worker nodes>
export OCI_NODE_MACHINE_TYPE=VM.Standard.E5.Flex
export OCI_NODE_MACHINE_TYPE_OCPUS=<number of OCPU per worker node>
export OCI_NODE_MACHINE_TYPE_MEMORY_IN_GBS=<memory in GB per worker node>
export OCI_MACHINE_POOL_CIDR_BLOCKS="<machine-pool-cidr>" # Example: 10.0.104.0/22
export OCI_MACHINE_POOL_IP_COUNT=<number of pod IPs per worker node>  # Max number of pods per worker node
export VCN_ID="<vcn-ocid>"
export SUBNET_CONTROL_PLANE_ENDPOINT_ID="<control-plane-endpoint-subnet-ocid>"
export SUBNET_CONTROL_PLANE_ID="<control-plane-subnet-ocid>"
export SUBNET_WORKER_ID="<worker-subnet-ocid>"

clusterctl generate cluster test \
--from cluster-template.yaml > rendered.yaml
