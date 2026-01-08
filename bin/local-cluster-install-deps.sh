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
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# cluster-components declare some dependencies we need to locally build
pushd cluster-components
helm dependency build
popd

###################
# Helper functions
###################

# Source parse helper function
source ./bin/_parser-helper.sh

# Now actually installs the various operator dependencies

function _helm_uninstall {
  helm_chart_name=$1
  ns=$2
  $HELM uninstall $helm_chart_name --namespace $ns || \
      echo "Non critical helm uninstall issue, skipping..."
}

function _kubectl_delete {
  url_or_file=$1
  extra_args=()
  if [ -n "${2}" ]; then
    extra_args+=("--namespace" "${2}")
  fi
  $KUBECTL delete "${extra_args[@]}" -f ${url_or_file} || \
      echo "Non critical deletion issue, skipping..."
}


############################################
# Statically hard-coded dependency required
############################################

# This is the transversal dependencies we don't actually check to
# Most of other helm chart can implicitely use them

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

# Same goes for the ingress
ingress_version=$(get_value ingressNginx version)

$KUBECTL get pods -n "ingress-nginx" -l app.kubernetes.io/name=ingress-nginx -l helm.sh/chart=ingress-nginx-${ingress_version} -o jsonpath="{.items[0].metadata.name}" 2>&1 || \
  ${HELM} upgrade --install ingress-nginx ingress-nginx \
        --version "${ingress_version}" \
        --repo https://kubernetes.github.io/ingress-nginx \
        --namespace ingress-nginx --create-namespace

$HELM upgrade --install keda \
      kedacore/keda \
      -n keda --create-namespace

LOCAL_PATH_PROVISIONER_DIR=${CLUSTER_TEMP_TMP}/local-path-provisioner
git clone https://github.com/rancher/local-path-provisioner.git \
    --depth 1 \
    "${LOCAL_PATH_PROVISIONER_DIR}"

pushd "${LOCAL_PATH_PROVISIONER_DIR}"

CONFIG_FILE=${LOCAL_PATH_PROVISIONER_DIR}/local-path-values.yaml
cat <<EOF >"${CONFIG_FILE}"
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
_helm_uninstall local-path local-path-storage

$HELM install ./deploy/chart/local-path-provisioner \
      --name-template local-path \
      --namespace local-path-storage \
      --create-namespace \
      -f "${CONFIG_FILE}"

CONFIG_FILE2=${LOCAL_PATH_PROVISIONER_DIR}/local-persistent-values.yaml
cat <<EOF >"${CONFIG_FILE2}"
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
  _helm_uninstall local-persistent local-path-storage

$HELM install ./deploy/chart/local-path-provisioner \
      --name-template local-persistent \
      --namespace local-path-storage \
      --create-namespace \
      -f "${CONFIG_FILE2}"
popd

############################################################################
# Dynamically toggled dependency by local-cluster*.yaml configuration files
############################################################################

argocd_enabled=$(get_value argocd enabled)
argocd_version=$(get_value argocd version)
ARGOCD_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"
if [ "${argocd_enabled}" = "true" ]; then
  # ARGOCD_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  $KUBECTL create namespace argocd || true
  $KUBECTL apply -n argocd -f ${ARGOCD_URL}
else
  _kubectl_delete ${ARGOCD_URL} argocd
fi

metallb_enabled=$(get_value metallb enabled)
metallb_version=$(get_value metallb version)
metallb_ns=$(get_value metallb namespace)
if [ "${metallb_enabled}" = "true" ]; then
  # ARGOCD_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  $HELM upgrade --install metallb \
        --version "${metallb_version}" \
        --namespace $metallb_ns \
        --create-namespace \
        metallb/metallb
else
  _helm_uninstall metallb $metallb_ns
fi

cnpg_version=$(get_value cloudnativePg version)
barmanplugin_version=$(get_value cloudnativePg barmanPluginVersion)
barmanplugin_url="https://github.com/cloudnative-pg/plugin-barman-cloud/releases/download/v${barmanplugin_version}/manifest.yaml"
barmanplugin_manifest="${CLUSTER_TEMP_TMP}/barman-cloud-plugin-manifest-${barmanplugin_version}.yaml"
wget --output-document="${barmanplugin_manifest}" \
     "${barmanplugin_url}"
cnpg_enabled=$(get_value cloudnativePg enabled)
if [ "${cnpg_enabled}" = "true" ]; then
  $HELM upgrade --install cloudnative-pg \
        --version "${cnpg_version}" \
        --namespace cnpg-system \
        --create-namespace \
        cnpg/cloudnative-pg

  # FIXME: Find a way to determine whether that's already installed
  _kubectl_delete "${barmanplugin_manifest}" || \
    $KUBECTL apply -f "${barmanplugin_manifest}"
else
  _helm_uninstall cloudnative-pg cnpg-system
  _kubectl_delete "${barmanplugin_manifest}"
fi

kafka_version=$(get_value kafka version)
kafka_enabled=$(get_value kafka enabled)
if [ "${kafka_enabled}" = "true" ]; then
  $HELM upgrade --install kafka-operator \
        --version "${kafka_version}" \
        --namespace kafka-system \
        --create-namespace \
        strimzi/strimzi-kafka-operator \
        --set watchAnyNamespace=true
else
  _helm_uninstall kafka-operator kafka-system
fi

cass_enabled=$(get_value cassandra enabled)
if [ "${cass_enabled}" = "true" ]; then
  cass_version=$(get_value cassandra version)
  $HELM upgrade --install k8ssandra-operator \
        --version "${cass_version}" \
        k8ssandra/k8ssandra-operator \
        -n k8ssandra-operator --create-namespace \
        --set global.clusterScoped=true
else
  _helm_uninstall k8ssandra-operator k8ssandra-operator
fi

elastic_version=$(get_value elasticsearch version)
elastic_enabled=$(get_value elasticsearch enabled)
if [ "${elastic_enabled}" = "true" ]; then
  $HELM upgrade --install eck-operator \
        --version "${elastic_version}" \
        elastic/eck-operator \
        -n elastic-system --create-namespace
else
  _helm_uninstall eck-operator elastic-system
fi

redis_version=$(get_value redis version)
redis_enabled=$(get_value redis enabled)
if [ "${redis_enabled}" = "true" ]; then
  $HELM upgrade --install redis-operator \
        --version "${redis_version}" \
        ot-helm/redis-operator \
        -n ot-operators --create-namespace
else
  _helm_uninstall redis-operator ot-operators
fi

PGBOUNCER_HELM_CHART_DIR=${CLUSTER_TEMP_TMP}/pgbouncer-helm-chart
git clone https://gitlab.cern.ch/pgbouncer/pgbouncer-helm-chart \
    --depth 1 \
    "${PGBOUNCER_HELM_CHART_DIR}"

pgbouncer_enabled=$(get_value pgbouncer enabled)
pushd "${PGBOUNCER_HELM_CHART_DIR}"
if [ "${pgbouncer_enabled}" = "true" ]; then
  $KUBECTL get pods -n pgbouncer -l "app=pgbouncer-pgbouncer" && \
    _helm_uninstall pgbouncer pgbouncer || \
      echo "It's fine!"

  # Disable default values which makes pods fail
  $HELM install ./chart \
        --name-template pgbouncer \
        --namespace pgbouncer \
        --set userlist.enabled=false \
        --set pgbouncerExporter.enabled=false \
        --create-namespace
else
  _helm_uninstall pgbouncer pgbouncer
fi
popd

rabbitmq_version=$(get_value rabbitmq version)
rabbitmq_file="external-manifests/rabbitmq/cluster-operator-${rabbitmq_version}.yaml"
messaging_topology_version=$(get_value rabbitmq messagingTopologyOperatorVersion)
mtv_file="external-manifests/rabbitmq/messaging-topology-operator-with-certmanager-${messaging_topology_version}.yaml"
rabbitmq_enabled=$(get_value rabbitmq enabled)
if [ "${rabbitmq_enabled}" = "true" ]; then
  ${KUBECTL} apply -f $rabbitmq_file
  ${KUBECTL} apply -f $mtv_file
else
  _kubectl_delete $rabbitmq_file
  _kubectl_delete $mtv_file
fi

############################################################
# Extra specific consideration for the cluster of type kind
############################################################


if [ "${KUBE_LOCAL_ENVIRONMENT}" = "kind" ]; then
    # Ingress specific setup for kind
    # TODO: Inline the file deploy.yaml in this repository?
    DEPLOY_FILE=https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    $KUBECTL apply -f ${DEPLOY_FILE}
fi
