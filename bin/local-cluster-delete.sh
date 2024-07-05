#!/usr/bin/env bash

# This script deletes the kind cluster

CLUSTER_CONTEXT=${1-local-cluster}
# Implementation detail, when providing the cluster-context to the kind command, it
# prefixed such context with kind-. So if called from the local-cluster.sh script, this
# may happen to provide it fully, so we must drop it.
CLUSTER_CONTEXT=$(echo $CLUSTER_CONTEXT | sed 's/kind-//g')

kind delete cluster --name $CLUSTER_CONTEXT
