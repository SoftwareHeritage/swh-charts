#!/usr/bin/env bash

set -x

CLUSTER_CONTEXT=${1-kind-local-cluster}
# Implementation detail, when providing the cluster-context to the kind command, it
# prefixed such context with kind-. So if called from the local-cluster.sh script, this
# may happen to provide it fully, so we must drop it.
CLUSTER_NAME=$(echo $CLUSTER_CONTEXT | sed 's/kind-//g')
KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"
NODES=$(kind get nodes --name $CLUSTER_NAME)

for node in $NODES; do
  $KUBECTL drain $node \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force
  docker restart $node
  $KUBECTL uncordon $node
done
