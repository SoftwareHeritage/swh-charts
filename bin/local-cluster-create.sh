#!/usr/bin/env bash

# This script triggers the installation of a local cluster (either minikube or
# kind).

CLUSTER_CONTEXT=${1-local-cluster}
KUBE_LOCAL_ENVIRONMENT=${2-kind}
WITH_INGRESS=${3-true}


if [ "${CLUSTER_CONTEXT}" = "minikube" ]; then
   KUBE_LOCAL_TECHNOLOGY=minikube
fi

case "$KUBE_LOCAL_ENVIRONMENT" in
    minikube)
        export MINIKUBE_IN_STYLE=false
        which minikube && minikube start --nodes 3 --memory 12288 --cpus 8 || \
            echo "Requires the minikube cli!" && exit 1
        ;;
    kind)
        # Implementation detail, when providing the cluster-context to the kind command, it
        # prefixed such context with kind-. So if called from the local-cluster.sh script, this
        # may happen to provide it fully, so we must drop it.
        CLUSTER_CONTEXT=$(echo $CLUSTER_CONTEXT | sed 's/kind-//g')

        CLUSTER_TEMP_CONFIG_FILE=$(mktemp)

        trap "rm -f ${CLUSTER_TEMP_CONFIG_FILE}" EXIT

        if [ "$WITH_INGRESS" = "ingress" ]; then
            # Install the ingress controller after cluster creation
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
        else
            # 4 nodes (1 control-plane, 3 workers) cluster config
            cat<<EOF >$CLUSTER_TEMP_CONFIG_FILE
---
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
EOF
        fi

        [ -f $CLUSTER_TEMP_CONFIG_FILE ] && cat $CLUSTER_TEMP_CONFIG_FILE

        # Create the cluster
        kind create cluster --kubeconfig ~/.kube/config.d/$CLUSTER_CONTEXT.yaml \
             --config $CLUSTER_TEMP_CONFIG_FILE \
             --name $CLUSTER_CONTEXT

        ;;
esac
