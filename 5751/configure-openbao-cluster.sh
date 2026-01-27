#!/usr/bin/env bash
# -*- eval: (setq-default sh-indentation 2) -*-

# This script configures the admin cluster for OpenBAO deployment:
# * create `openbao` namespace
# * install openbao helm chart inside `openbao` namespace

set -e

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/../bin"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
  source "${SCRIPT_DIR}/.helper-functions.sh"
fi

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
  source "${SCRIPT_DIR}/.helper-functions.sh"
else
  echo "<${ENV_FILE}> is required, failing."
  exit 1
fi

DESCRIPTION="Configure openbao in admin cluster"

if [ "${1}" = "-h" -o "${1}" = "--help" ]; then
  script_usage "${DESCRIPTION}"
  exit 1
fi

CLUSTER_NAME=openbao
DEBUG_INSTRUCTIONS=

set_variables_for_cluster ${CLUSTER_NAME}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      set -x
      export DEBUG_INSTRUCTIONS=1
      shift
      ;;
    -r|--reset)
      cluster_reset "${CLUSTER_NAME}"
      shift
      ;;
    -c|--create)
      cluster_create "${CLUSTER_NAME}"
      shift
      ;;
    -d|--delete)
      cluster_delete "${CLUSTER_NAME}"
      exit 0
      ;;
    -h|--help)
      script_usage "${DESCRIPTION}"
      shift
      ;;
    *)
      echo "Unknown option <$1>"
      script_usage "${DESCRIPTION}"
      exit 1
      ;;
  esac
done

create_shared_ca_files

${HELM} repo add jetstack https://charts.jetstack.io
${HELM} repo add metallb https://metallb.github.io/metallb
${HELM} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
${HELM} repo add openbao https://openbao.github.io/openbao-helm
${HELM} repo update jetstack metallb ingress-nginx openbao

install_or_skip cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true --set installCRDs=true
install_or_skip metallb metallb/metallb --namespace metallb
install_or_skip ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx

execute_or_skip ${KUBECTL} create namespace "${NS_OPENBAO}"

# Inject shared ca
execute_or_skip ${KUBECTL} create secret tls shared-ca \
  --namespace cert-manager --cert=$CA_CERT_FILECRT --key=$CA_CERT_FILEKEY
execute_or_skip ${KUBECTL} create configmap \
  --namespace "${NS_OPENBAO}" shared-ca --from-file=ca.crt=$CA_CERT_FILECRT

# Enable ingress controller load balancer IP allocation through metallb
${KUBECTL} wait pod --all --for=condition=Ready --timeout=60s -n metallb

${KUBECTL} apply -f - <<EOF
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

OPENBAO_VALUES_FILE=$TEMP_DIR/openbao-values.yaml
cat > "${OPENBAO_VALUES_FILE}" << EOF
injector:
  logLevel: trace
server:
  logLevel: trace
  # Add some extra dns records so we don't need an extra dns
  hostAliases:
  # Make vso ingress hostname resolvable
  - ip: ${VSO_INGRESS_IP}
    hostnames:
    - ${VSO_INGRESS_HOSTNAME}
  # Make openbao ingress hostname resolvable in-cluster too
  - ip: ${OPENBAO_INGRESS_IP}
    hostnames:
    - ${OPENBAO_INGRESS_HOSTNAME}
  # Enable the dev mode (in-memory)
  dev:
    enabled: true
  # Enable ingress so openbao is reachable from outside the cluster too
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
    - host: ${OPENBAO_INGRESS_HOSTNAME}
    tls:
    - secretName: openbao-tls
      hosts:
      - ${OPENBAO_INGRESS_HOSTNAME}
  volumes:
  - name: ca
    configMap:
      name: shared-ca
  volumeMounts:
  - name: ca
    mountPath: /etc/openbao/ca
    readOnly: true
  certs:
    secretName: openbao-tls
    caBundle: /etc/openbao/ca/ca.crt
EOF

install_or_skip openbao openbao/openbao \
  --namespace ${NS_OPENBAO} \
  --values "${OPENBAO_VALUES_FILE}"

# Create a cluster issuer shared-ca-issuer and generate a certificate for openbao
${KUBECTL} apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: shared-ca-issuer
spec:
  ca:
    secretName: shared-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openbao-tls
  namespace: openbao   # Helm release namespace
spec:
  secretName: openbao-tls   # will contain tls.crt & tls.key
  dnsNames:
  - ${OPENBAO_INGRESS_HOSTNAME}   # FQDN that the vso pod will use
  issuerRef:
    name: shared-ca-issuer
    kind: ClusterIssuer
EOF

${KUBECTL} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

cat <<EOF
##############################################
## OpenBAO cluster configured successfully! ##

Configure your local /etc/hosts to access OpenBAO instance through ingress load balancer IP
echo "${OPENBAO_INGRESS_IP} ${OPENBAO_INGRESS_HOSTNAME}" | sudo tee -a /etc/hosts

Access ui at: http://${OPENBAO_INGRESS_HOSTNAME} (token=root)

##############################################
EOF
