#!/usr/bin/env bash

# This scripts installs the necessary dependencies for the charts to work. It uses the
# /cluster-configuration/values.yaml to retrieve the version of the charts to use. So
# the local cluster installation reflects the version of what's used by actual
# production cluster.

set -e

CLUSTER_CONTEXT=${1-kind-local-cluster}
KUBE_LOCAL_ENVIRONMENT=${2-kind}

if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq is not installed." >&2
  exit 1
fi

KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"
HELM="helm --kube-context ${CLUSTER_CONTEXT}"

CLUSTER_TEMP_TMP=$(mktemp -d)
trap 'rm -rf ${CLUSTER_TEMP_TMP}' EXIT

# Install the helm repo dependencies
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo add strimzi https://strimzi.io/charts/
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add jetstack https://charts.jetstack.io
helm repo add elastic https://helm.elastic.co
helm repo add ot-helm https://ot-container-kit.github.io/helm-charts/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add kedacore https://kedacore.github.io/charts
helm repo add gitlab-runner https://charts.gitlab.io
helm repo update

# cluster-components declare some dependencies we need to locally build
pushd cluster-components
helm dependency build
popd

# Source parse helper function
source ./bin/_parser-helper.sh

# Now actually installs the various operator dependencies

ingress_version=$(get_value ingressNginx version)
${HELM} upgrade --install ingress-nginx ingress-nginx \
      --version "${ingress_version}" \
      --repo https://kubernetes.github.io/ingress-nginx \
      --namespace ingress-nginx --create-namespace

cloudnativepg_version=$(get_value cloudnativePg version)
$HELM upgrade --install cloudnative-pg \
      --version "${cloudnativepg_version}" \
      --namespace cnpg-system \
      --create-namespace \
      cnpg/cloudnative-pg

kafka_version=$(get_value kafka version)
$HELM upgrade --install kafka-operator \
      --version "${kafka_version}" \
      --namespace kafka-system \
      --create-namespace \
      strimzi/strimzi-kafka-operator \
      --set watchAnyNamespace=true

certmanager_version=$(get_value certManager version)
$HELM upgrade --install cert-manager \
      --version "${certmanager_version}" \
      jetstack/cert-manager \
      --namespace cert-manager --create-namespace \
      --set crds.enabled=true \
      --set installCRDs=true

# Cannot have those since prometheus is not necessarily installed yet.
      # --set prometheus.enabled=true \
      # --set prometheus.servicemonitor.enabled=true \

cassandra_version=$(get_value cassandra version)
$HELM upgrade --install k8ssandra-operator \
      --version "${cassandra_version}" \
      k8ssandra/k8ssandra-operator \
      -n k8ssandra-operator --create-namespace \
      --set global.clusterScoped=true

elasticsearch_version=$(get_value elasticsearch version)
$HELM upgrade --install eck-operator \
      --version "${elasticsearch_version}" \
      elastic/eck-operator \
      -n elastic-system --create-namespace

redis_version=$(get_value redis version)
$HELM upgrade --install redis-operator \
      --version "${redis_version}" \
      ot-helm/redis-operator \
      -n ot-operators --create-namespace \

$HELM upgrade --install keda \
      kedacore/keda \
      -n keda --create-namespace

PGBOUNCER_LOCAL_PATH_PROVISIONER_DIR=${CLUSTER_TEMP_TMP}/local-path-provisioner

git clone https://github.com/rancher/local-path-provisioner.git \
    --depth 1 \
    "${PGBOUNCER_LOCAL_PATH_PROVISIONER_DIR}"
pushd "${PGBOUNCER_LOCAL_PATH_PROVISIONER_DIR}"

CONFIG_FILE=${PGBOUNCER_LOCAL_PATH_PROVISIONER_DIR}/local-path-values.yaml
cat<<EOF >"${CONFIG_FILE}"
configmap:
  name: swh-local-path-provisioner
nameOverride: swh-local-path-provisioner
workerThreads: 8
nodePathMap:
  - node: DEFAULT_PATH_FOR_NON_LISTED_NODES
    paths:
      - /tmp/k8s-ephemeral-storage
EOF

# For idempotency, just in case we call multiple times this script
$KUBECTL get storageclass local-path && \
  $HELM uninstall local-path --namespace local-path-storage || \
    echo "It's fine!"

$HELM install ./deploy/chart/local-path-provisioner \
      --name-template local-path \
      --namespace local-path-storage \
      --create-namespace \
      -f "${CONFIG_FILE}"

CONFIG_FILE2=${PGBOUNCER_LOCAL_PATH_PROVISIONER_DIR}/local-persistent-values.yaml
cat<<EOF >"${CONFIG_FILE2}"
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

# For idempotency, just in case we call multiple times this script
$KUBECTL get storageclass local-persistent && \
  $HELM uninstall local-persistent --namespace local-path-storage || \
    echo "It's fine!"

$HELM install ./deploy/chart/local-path-provisioner \
      --name-template local-persistent \
      --namespace local-path-storage \
      --create-namespace \
      -f "${CONFIG_FILE2}"
popd

PGBOUNCER_HELM_CHART_DIR=${CLUSTER_TEMP_TMP}/pgbouncer-helm-chart

git clone https://gitlab.cern.ch/pgbouncer/pgbouncer-helm-chart \
    --depth 1 \
    "${PGBOUNCER_HELM_CHART_DIR}"
pushd "${PGBOUNCER_HELM_CHART_DIR}"

$KUBECTL get pods -n pgbouncer -l "app=pgbouncer-pgbouncer" && \
  $HELM uninstall pgbouncer --namespace pgbouncer || \
    echo "It's fine!"

# Disable default values which makes pods fail
$HELM install ./chart \
      --name-template pgbouncer \
      --namespace pgbouncer \
      --set userlist.enabled=false \
      --set pgbouncerExporter.enabled=false \
      --create-namespace

popd

if [ "${KUBE_LOCAL_ENVIRONMENT}" = "kind" ]; then
    # Ingress specific setup for kind
    # TODO: Inline the file deploy.yaml in this repository?
    DEPLOY_FILE=https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    $KUBECTL apply -f ${DEPLOY_FILE}

    $KUBECTL wait \
        --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s
fi

rabbitmq_version=$(get_value rabbitmq version)
${KUBECTL} apply -f external-manifests/rabbitmq/cluster-operator-"${rabbitmq_version}".yaml

messaging_topology_version=$(get_value rabbitmq messagingTopologyOperatorVersion)
${KUBECTL} apply -f external-manifests/rabbitmq/messaging-topology-operator-with-certmanager-"${messaging_topology_version}".yaml
