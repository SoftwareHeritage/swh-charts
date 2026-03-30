#!/usr/bin/env bash

# This script triggers the installation of a local cluster (either minikube or
# kind).

CLUSTER_CONTEXT=${1-kind-local-cluster}
KUBE_LOCAL_ENVIRONMENT=${2-kind}

if [ "${CLUSTER_CONTEXT}" = "minikube" ]; then
   KUBE_LOCAL_TECHNOLOGY=minikube
fi

# Source helper functions used throughout the script
source ./bin/_helper-functions.sh
_init_setup_and_checks

case "$KUBE_LOCAL_ENVIRONMENT" in
    minikube)
        export MINIKUBE_IN_STYLE=false
        which minikube && minikube start --nodes 3 --memory 12288 --cpus 8 || \
            echo "Requires the minikube cli!" && exit 1
        ;;
    kind)
        CLUSTER_CONTEXT=$(_get_cluster_context "${CLUSTER_CONTEXT}")

        CLUSTER_TEMP_CONFIG_FILE=$(mktemp)

        trap "rm -f ${CLUSTER_TEMP_CONFIG_FILE}" EXIT

        # 4 nodes (1 control-plane, 3 workers) cluster config
        cat<<EOF >$CLUSTER_TEMP_CONFIG_FILE
---
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
- role: worker
EOF

        [ -f $CLUSTER_TEMP_CONFIG_FILE ] && cat $CLUSTER_TEMP_CONFIG_FILE

        # Create the cluster
        kind create cluster --kubeconfig ~/.kube/config.d/$CLUSTER_CONTEXT.yaml \
             --config $CLUSTER_TEMP_CONFIG_FILE \
             --name $CLUSTER_CONTEXT
        # Note: Annoyingly, kind will systematically create the cluster context as
        # "kind-$yourChosenClusterContext"

        ;;
esac
