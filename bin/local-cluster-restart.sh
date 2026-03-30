#!/usr/bin/env bash

set -x

CLUSTER_CONTEXT=${1-local-cluster}

# Source helper functions used throughout the script
source ./bin/_helper-functions.sh
_init_setup_and_checks

CLUSTER_NAME=$(_get_cluster_context $CLUSTER_CONTEXT)
NODES=$(kind get nodes --name $CLUSTER_NAME)

for node in $NODES; do
  $KUBECTL drain $node \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force
  docker restart $node
  $KUBECTL uncordon $node
done
