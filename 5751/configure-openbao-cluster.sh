#!/usr/bin/env bash

# This script configures the admin cluster for OpenBAO deployment:
# * create `openbao` namespace
# * install openbao helm chart inside `openbao` namespace

set -xe

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/../bin"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

if [[ "$1" == "--reset" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_OPENBAO}"
  "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT_OPENBAO}" kind
elif [[ "$1" == "--cleanup" ]]; then
  # If --cleanup is set, remove existing resources
  ${HELM_OPENBAO} uninstall openbao || true
#  $KUBECTL_OPENBAO delete namespace "${NS_OPENBAO}" || true
fi

${HELM_OPENBAO} repo add jetstack https://charts.jetstack.io
${HELM_OPENBAO} repo add metallb https://metallb.github.io/metallb
${HELM_OPENBAO} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
${HELM_OPENBAO} repo add openbao https://openbao.github.io/openbao-helm
${HELM_OPENBAO} repo update jetstack metallb ingress-nginx openbao

${HELM_OPENBAO} install cert-manager jetstack/cert-manager --namespace "cert-manager" --create-namespace --set crds.enabled=true --set installCRDs=true > /dev/null 2>&1 || echo "<cert-manager> already installed!"
${HELM_OPENBAO} install metallb metallb/metallb --namespace metallb --create-namespace > /dev/null 2>&1 || echo "<metallb> already installed!"
${HELM_OPENBAO} install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace > /dev/null 2>&1 || echo "<ingress-nginx> already installed!"

# Enable ingress controller load balancer IP allocation through metallb
${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n metallb

${KUBECTL_OPENBAO} apply -f - <<EOF
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: "local-metallb-pool-ingress"
  namespace: metallb
spec:
  addresses:
    - ${OPENBAO_INGRESS_IP}/24
  serviceAllocation:
    namespaces:
    - ingress-nginx
    priority: 50
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: "l2-advertisement-ingress"
  namespace: metallb
spec:
  ipAddressPools:
  - "local-metallb-pool-ingress"
EOF

${HELM_OPENBAO} upgrade \
  --install openbao openbao/openbao \
  --set "injector.logLevel=trace" \
  --set "server.logLevel=trace" \
  --set "server.dev.enabled=true" \
  --set "server.ingress.enabled=true" \
  --set "server.ingress.ingressClassName=nginx" \
  --set "server.ingress.hosts[0].host=${OPENBAO_INGRESS_HOSTNAME}" \
  --set "server.hostAliases[0].ip=${VSO_INGRESS_IP}" \
  --set "server.hostAliases[0].hostnames[0]=${VSO_INGRESS_HOSTNAME}" \
  -n "${NS_OPENBAO}" \
  --create-namespace

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

cat <<EOF
##############################################
## OpenBAO cluster configured successfully! ##

Configure your local /etc/hosts to access OpenBAO instance through ingress load balancer IP
echo "${OPENBAO_INGRESS_IP} ${OPENBAO_INGRESS_HOSTNAME}" | sudo tee -a /etc/hosts

Access ui at: http://${OPENBAO_INGRESS_HOSTNAME} (token=root)

##############################################
EOF
