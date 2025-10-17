#!/usr/bin/env bash

# This simplifies the update of the crds for rabbitmq operators:
# - cluster-operator.yaml
# - messaging-topology-operator-with-certmanager.yaml

# NOTE: This is brittle and might break if upstream chooses to change their release
# process

# Use:
# cd swh-charts && ./bin/rabbitmq-update-crds.sh 2.17.0 1.18.0

# TODO: Reuse parsing of the default values in cluster-configuration/values.yaml
# to extract versions
version=$1
version_messaging=$2

CLUSTER_OPERATOR_URL=https://github.com/rabbitmq/cluster-operator/releases/download
MESSAGING_TOPO_OPERATOR_URL=https://github.com/rabbitmq/messaging-topology-operator/releases/download

wget "${CLUSTER_OPERATOR_URL}/v${version}/cluster-operator.yml" \
    -O ./cluster-configuration/templates/rabbitmq-operator/cluster-operator-${version}.yaml

wget "${MESSAGING_TOPO_OPERATOR_URL}/v${version_messaging}/messaging-topology-operator-with-certmanager.yaml" \
    -O ./cluster-configuration/templates/rabbitmq-operator/messaging-topology-operator-with-certmanager-${version_messaging}.yaml
