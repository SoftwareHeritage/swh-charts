#!/usr/bin/env bash

# This script cleans up the charts dependencies

CLUSTER_CONTEXT=${1-kind-local-cluster}

HELM="helm --kube-context $CLUSTER_CONTEXT"

$HELM uninstall -n ingress-nginx ingress-nginx

$HELM uninstall -n default rabbitmq-operator

$HELM uninstall -n cnpg-system cloudnative-pg

$HELM uninstall -n kafka-system kafka-operator

$HELM uninstall -n cert-manager cert-manager

$HELM uninstall -n k8ssandra-operator k8ssandra-operator
