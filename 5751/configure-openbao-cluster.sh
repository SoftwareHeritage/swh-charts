#!/usr/bin/env bash

# This script configures the admin cluster for OpenBAO deployment:
# * create `openbao` namespace
# * install openbao helm chart inside `openbao` namespace

set -e
set -x

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/../bin"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

# To configure properly the install_or_skip function
HELM=$HELM_OPENBAO

if [[ "$1" == "--delete" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_OPENBAO}"
  exit 0
elif [[ "$1" == "--reset" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_OPENBAO}"
  "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT_OPENBAO}" kind
elif [[ "$1" == "--cleanup" ]]; then
  # If --cleanup is set, remove existing resources
  ${HELM_OPENBAO} uninstall openbao || true
#  $KUBECTL_OPENBAO delete namespace "${NS_OPENBAO}" || true
fi

if [ ! -d $CA_CERT_DIR ]; then
    mkdir -p $CA_CERT_DIR
    # Generate private rsa key
    openssl genrsa -out $CA_CERT_FILEKEY 4096

    # Ensure no issues occurred
    [ ! -f $CA_CERT_FILEKEY ] && echo "<$CA_CERT_FILEKEY> must exist!" && exit 1

    # Self-signed shared root certificate in between kind clusters
    openssl req -x509 -new -nodes -key $CA_CERT_FILEKEY \
            -sha256 -days 3650 \
            -subj "/CN=shared-local-clusters-ca" \
            -out $CA_CERT_FILECRT
    # Ensure no issues occurred
    [ ! -f $CA_CERT_FILECRT ] && echo "<$CA_CERT_FILECRT> must exist!" && exit 1
fi

${HELM_OPENBAO} repo add jetstack https://charts.jetstack.io
${HELM_OPENBAO} repo add metallb https://metallb.github.io/metallb
${HELM_OPENBAO} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
${HELM_OPENBAO} repo add openbao https://openbao.github.io/openbao-helm
${HELM_OPENBAO} repo update jetstack metallb ingress-nginx openbao

install_or_skip cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true --set installCRDs=true
install_or_skip metallb metallb/metallb --namespace metallb
install_or_skip ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx

execute_or_skip ${KUBECTL_OPENBAO} create namespace "${NS_OPENBAO}"

# Inject shared ca
execute_or_skip ${KUBECTL_OPENBAO} create secret tls shared-ca \
  --namespace cert-manager --cert=$CA_CERT_FILECRT --key=$CA_CERT_FILEKEY
execute_or_skip ${KUBECTL_OPENBAO} create configmap \
  --namespace "${NS_OPENBAO}" shared-ca --from-file=ca.crt=$CA_CERT_FILECRT

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
${KUBECTL_OPENBAO} apply -f - <<EOF
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

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

cat <<EOF
##############################################
## OpenBAO cluster configured successfully! ##

Configure your local /etc/hosts to access OpenBAO instance through ingress load balancer IP
echo "${OPENBAO_INGRESS_IP} ${OPENBAO_INGRESS_HOSTNAME}" | sudo tee -a /etc/hosts

Access ui at: http://${OPENBAO_INGRESS_HOSTNAME} (token=root)

##############################################
EOF
