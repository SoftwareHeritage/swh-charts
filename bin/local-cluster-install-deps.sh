#!/usr/bin/env bash

# This scripts installs the necessary dependencies for the charts to work

CLUSTER_CONTEXT=${1-kind-local-cluster}

HELM="helm --kube-context $CLUSTER_CONTEXT"

# Install the helm repo dependencies
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo add strimzi https://strimzi.io/charts/
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add jetstack https://charts.jetstack.io
helm repo add elastic https://helm.elastic.co
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo update

# Now actually installs the various operator dependencies

$HELM upgrade --install ingress-nginx ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --namespace ingress-nginx --create-namespace

$HELM upgrade --install rabbitmq-operator \
     bitnami/rabbitmq-cluster-operator

$HELM upgrade --install cloudnative-pg \
     --namespace cnpg-system \
     --create-namespace \
     cnpg/cloudnative-pg

$HELM upgrade --install kafka-operator \
     --namespace kafka-system \
     --create-namespace \
     strimzi/strimzi-kafka-operator \
     --set watchAnyNamespace=true

$HELM upgrade --install cert-manager \
     jetstack/cert-manager \
     --namespace cert-manager --create-namespace \
     --set installCRDs=true

$HELM upgrade --install k8ssandra-operator \
     k8ssandra/k8ssandra-operator \
     -n k8ssandra-operator --create-namespace \
     --set global.clusterScoped=true

$HELM upgrade --install eck-operator \
     elastic/eck-operator \
     -n elastic-system --create-namespace

$HELM upgrade --install redis-operator \
     ot-helm/redis-operator \
     -n ot-operators --create-namespace \
     --version 0.15.10
