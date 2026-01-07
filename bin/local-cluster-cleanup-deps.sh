#!/usr/bin/env bash

# This script cleans up the charts dependencies

CLUSTER_CONTEXT=${1-kind-local-cluster}

HELM="helm --kube-context ${CLUSTER_CONTEXT}"
KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"

# Source parse helper function
source ./bin/_parser-helper.sh

$HELM uninstall -n ingress-nginx ingress-nginx

$HELM uninstall -n cnpg-system cloudnative-pg

$HELM uninstall -n kafka-system kafka-operator

$HELM uninstall -n cert-manager cert-manager

$HELM uninstall -n k8ssandra-operator k8ssandra-operator

$HELM uninstall -n ot-operators redis-operator

$HELM uninstall -n keda keda

$HELM uninstall -n pgbouncer pgbouncer

$HELM uninstall -n elastic-system eck-operator

$HELM uninstall -n local-path-storage local-path

$HELM uninstall -n local-path-storage local-persistent

messaging_topology_version=$(get_value rabbitmq messagingTopologyOperatorVersion)
${KUBECTL} delete -f external-manifests/rabbitmq/messaging-topology-operator-with-certmanager-"${messaging_topology_version}".yaml

rabbitmq_version=$(get_value rabbitmq version)
${KUBECTL} delete -f external-manifests/rabbitmq/cluster-operator-"${rabbitmq_version}".yaml

argocd_version=$(get_value argocd version)
ARGOCD_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"
$KUBECTL delete -n argocd -f ${ARGOCD_URL}
