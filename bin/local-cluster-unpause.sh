#!/usr/bin/env bash

# This script unpauses the local cluster

CLUSTER_CONTEXT=${1-local-cluster}
KUBE_LOCAL_ENVIRONMENT=${2-kind}

if [ "${CLUSTER_CONTEXT}" = "minikube" ]; then
   KUBE_LOCAL_TECHNOLOGY=minikube
fi

case "$KUBE_LOCAL_ENVIRONMENT" in
    minikube)
        which minikube || (echo "Requires the minikube cli!" && exit 1)
        minikube unpause
        ;;
    kind)
        # Implementation detail, when providing the cluster-context to the kind command, it
        # prefixed such context with kind-. So if called from the local-cluster.sh script, this
        # may happen to provide it fully, so we must drop it.
        CLUSTER_CONTEXT=$(echo $CLUSTER_CONTEXT | sed 's/kind-//g')
        which kind || (echo "Requires the kind cli!" && exit 1)

        kind get nodes --name $CLUSTER_CONTEXT | xargs docker unpause
        ;;
esac
