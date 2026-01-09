#!/usr/bin/env bash

# This script cleans up the charts dependencies

CLUSTER_CONTEXT=${1-kind-local-cluster}

# Source helper functions used throughout the script
source ./bin/_helper-functions.sh

#########
# Script
#########

_init_setup_and_checks

_helm_uninstall cloudnative-pg cnpg-system
_helm_uninstall kafka-operator kafka-system
_helm_uninstall k8ssandra-operator k8ssandra-operator
_helm_uninstall redis-operator ot-operators
_helm_uninstall keda keda
_helm_uninstall pgbouncer pgbouncer
_helm_uninstall eck-operator elastic-system
_helm_uninstall local-path local-path-storage
_helm_uninstall local-persistent local-path-storage
_helm_uninstall ingress-nginx ingress-nginx
_helm_uninstall metallb metallb
_helm_uninstall cert-manager cert-manager

messaging_topology_version=$(get_value rabbitmq messagingTopologyOperatorVersion)
_kubectl_delete "external-manifests/rabbitmq/messaging-topology-operator-with-certmanager-${messaging_topology_version}.yaml"

rabbitmq_version=$(get_value rabbitmq version)
_kubectl_delete "external-manifests/rabbitmq/cluster-operator-${rabbitmq_version}.yaml"

argocd_version=$(get_value argocd version)
ARGOCD_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"
_kubectl_delete "${ARGOCD_URL}" argocd
