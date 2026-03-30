#!/usr/bin/env bash

# This script unpauses the local cluster

CLUSTER_CONTEXT=${1-local-cluster}
KUBE_LOCAL_ENVIRONMENT=${2-kind}

if [ "${CLUSTER_CONTEXT}" = "minikube" ]; then
   KUBE_LOCAL_TECHNOLOGY=minikube
fi
# Source helper functions used throughout the script
source ./bin/_helper-functions.sh
_init_setup_and_checks

case "$KUBE_LOCAL_ENVIRONMENT" in
    minikube)
        which minikube || (echo "Requires the minikube cli!" && exit 1)
        minikube unpause
        ;;
    kind)
        CLUSTER_CONTEXT=$(_get_cluster_context $CLUSTER_CONTEXT)
        which kind || (echo "Requires the kind cli!" && exit 1)

        kind get nodes --name $CLUSTER_CONTEXT | xargs docker unpause
        ;;
    *)
        echo "Unknown local-environment <$KUBE_LOCAL_ENVIRONMENT>, do nothing";

esac
