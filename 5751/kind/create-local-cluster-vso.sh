#!/usr/bin/env bash

# This script triggers the installation of a local cluster (either minikube or
# kind).

CLUSTER_CONTEXT=${1-local-cluster-kind-vso}
CLUSTER_CONTEXT=$(echo $CLUSTER_CONTEXT | sed 's/kind-//g')
CLUSTER_TEMP_CONFIG_FILE=$(mktemp)
trap "rm -f ${CLUSTER_TEMP_CONFIG_FILE}" EXIT

# cat<<EOF >$CLUSTER_TEMP_CONFIG_FILE
# kind: Cluster
# apiVersion: kind.x-k8s.io/v1alpha4
# nodes:
#   - role: control-plane
#     extraPortMappings: []   # optional, keep empty if you don’t need ports
#     # Ensure the node runs privileged (needed for systemd)
#     extraMounts:
#       - hostPath: /var/run/docker.sock
#         containerPath: /var/run/docker.sock
#     # Disable any user‑ns remap that Docker might have applied
#     kubeadmConfigPatches:
#       - |
#         kind: InitConfiguration
#         nodeRegistration:
#           kubeletExtraArgs:
#             container-runtime: remote
#             container-runtime-endpoint: unix:///var/run/containerd/containerd.sock
# EOF

# [ -f $CLUSTER_TEMP_CONFIG_FILE ] && cat $CLUSTER_TEMP_CONFIG_FILE

# Create the cluster
# kind create cluster --kubeconfig ~/.kube/config.d/$CLUSTER_CONTEXT.yaml \
#      --config $CLUSTER_TEMP_CONFIG_FILE \
#      --name $CLUSTER_CONTEXT \
#      --verbosity 6

# kind create cluster --kubeconfig ~/.kube/config.d/$CLUSTER_CONTEXT.yaml \
#      --config $CLUSTER_TEMP_CONFIG_FILE \
#      --name $CLUSTER_CONTEXT \
#      --wait 30s \
#      --image kindest/node:v1.32.2 \
#      --verbosity 6

kind create cluster --kubeconfig ~/.kube/config.d/$CLUSTER_CONTEXT.yaml \
     --name $CLUSTER_CONTEXT \
     --verbosity 6
