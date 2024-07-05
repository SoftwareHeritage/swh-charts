#!/usr/bin/env bash

# This script triggers the installation of a local cluster (with the kind tool). Kind
# was chosen because for the case of running cassandra locally, we need multiple nodes
# and it was easier with kind.

CLUSTER_CONTEXT=${1-local-cluster}

# Implementation detail, when providing the cluster-context to the kind command, it
# prefixed such context with kind-. So if called from the local-cluster.sh script, this
# may happen to provide it fully, so we must drop it.
CLUSTER_CONTEXT=$(echo $CLUSTER_CONTEXT | sed 's/kind-//g')

CLUSTER_TEMP_CONFIG_FILE=$(mktemp)

trap "rm -f ${CLUSTER_TEMP_CONFIG_FILE}" EXIT

# 4 nodes (1 control-plane, 3 workers) cluster config
cat<<EOF >$CLUSTER_TEMP_CONFIG_FILE
---
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
- role: worker
EOF

[ -f $CLUSTER_TEMP_CONFIG_FILE ] && cat $CLUSTER_TEMP_CONFIG_FILE

# Create the cluster
kind create cluster --kubeconfig ~/.kube/config.d/$CLUSTER_CONTEXT.yaml \
     --config $CLUSTER_TEMP_CONFIG_FILE \
     --name $CLUSTER_CONTEXT
