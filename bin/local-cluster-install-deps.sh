#!/usr/bin/env bash

# This scripts installs the necessary dependencies for the charts to work

CLUSTER_CONTEXT=${1-kind-local-cluster}
KUBE_LOCAL_ENVIRONMENT=${2-kind}

KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"
HELM="helm --kube-context $CLUSTER_CONTEXT"

# Install the helm repo dependencies
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo add strimzi https://strimzi.io/charts/
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add jetstack https://charts.jetstack.io
helm repo add elastic https://helm.elastic.co
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# cluster-components declare some dependencies we need to locally build
pushd cluster-components
helm dependency build
popd

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
     --set crds.enabled=true

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
     --version 0.18.3

$HELM upgrade --install keda \
      kedacore/keda \
      -n keda --create-namespace

git clone https://github.com/rancher/local-path-provisioner.git \
    --depth 1 \
    /tmp/local-path-provisioner
pushd /tmp/local-path-provisioner

CONFIG_FILE=/tmp/local-path-provisioner/local-path-values.yaml
cat<<EOF >$CONFIG_FILE
configmap:
  name: swh-local-path-provisioner
nameOverride: swh-local-path-provisioner
workerThreads: 8
nodePathMap:
  - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
    paths:
      - /tmp/k8s-ephemeral-storage
EOF
$HELM install ./deploy/chart/local-path-provisioner \
      --name-template local-path \
      --namespace local-path-storage \
      -f $CONFIG_FILE

CONFIG_FILE2=/tmp/local-path-provisioner/local-persistent-values.yaml
cat<<EOF >$CONFIG_FILE2
configmap:
  name: swh-local-persistent-provisioner
nameOverride: swh-local-persistent-provisioner
nodePathMap:
  - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
    paths:
      - /srv/kubernetes/volumes/
storageClass:
  create: true
  defaultClass: false
  name: local-persistent
  reclaimPolicy: Retain
EOF

$HELM install ./deploy/chart/local-path-provisioner \
      --name-template local-persistent \
      --namespace local-path-storage \
      -f $CONFIG_FILE2
popd

if [ "${KUBE_LOCAL_ENVIRONMENT}" = "kind" ]; then
    # Ingress specific setup for kind
    # TODO: Inline the file deploy.yaml in this repository?
    DEPLOY_FILE=https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    $KUBECTL apply -f $DEPLOY_FILE

    $KUBECTL wait \
        --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s

fi
