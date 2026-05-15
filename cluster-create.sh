set -x
COMPUTE_COMPARTMENT_ID=ocid1.compartment.oc1..aaaaaaaap54r7edm7qrq2wmpiumcmhr6tj6iz2eqiq7uc57xpqggml32q4xa \
NETWORK_COMPARTMENT_ID=ocid1.compartment.oc1..aaaaaaaatbw2dg23vvqyaikcmxws5rhqe5u6cc42jxoixbxdfdulc5cjzraa \
OCI_SSH_KEY=$(cat ~/.ssh/id_rsa.pub) \
KUBERNETES_VERSION=v1.34.3 \
OCI_IMAGE_ID=ocid1.image.oc1.iad.aaaaaaaampi5gpfcc37aijpfii5nxsaf6ndrrcyx3z2eevz4cmrmtlh35ega \
CONTROL_PLANE_MACHINE_COUNT=1 \
NAMESPACE=default \
WORKER_MACHINE_COUNT=2 \
OCI_NODE_MACHINE_TYPE=VM.Standard.E5.Flex \
OCI_NODE_MACHINE_TYPE_OCPUS=2 \
OCI_NODE_MACHINE_TYPE_MEMORY_IN_GBS=32 \
OCI_MACHINE_POOL_CIDR_BLOCKS=10.0.104.0/22 \
OCI_MACHINE_POOL_IP_COUNT=32 \
CLUSTER_POD_CIDR=10.0.104.0/22 \
VCN_ID=ocid1.vcn.oc1.iad.amaaaaaa22cz7wqayxhffum4bhsu6wywl5vw5fhu3vy4mq7gtw3wbugect3q \
SUBNET_CONTROL_PLANE_ENDPOINT_ID=ocid1.subnet.oc1.iad.aaaaaaaasl77s5c4kzoekxqb3yc3ucw5qgsoi7a64ms32pqmrr2pzg5hgmja \
SUBNET_CONTROL_PLANE_ID=ocid1.subnet.oc1.iad.aaaaaaaatmyiu3fuqt2khszw5f7dqyhvduzw4fpko6uriqstcfzeqaprbpma \
SUBNET_WORKER_ID=ocid1.subnet.oc1.iad.aaaaaaaatmyiu3fuqt2khszw5f7dqyhvduzw4fpko6uriqstcfzeqaprbpma \
clusterctl generate cluster test \
--from cluster-template.yaml > rendered.yaml
