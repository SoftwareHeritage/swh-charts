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

CLUSTER_NAME=$1
if [ -z "${CLUSTER_NAME}" ]; then
  CLUSTER_NAME=admin
else
  shift
fi

case "${CLUSTER_NAME}" in
  admin|openbao)
    # Ok, nothing to do
  ;;
  *)
    echo "Unsupported cluster name <$CLUSTER_NAME>! Must be one of {admin, openbao}"
    exit 1
  ;;
esac

set_variables_for_cluster ${CLUSTER_NAME}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      set -x
      export DEBUG_INSTRUCTIONS=1
      shift
      ;;
    -r|--recreate)
      cluster_recreate "${CLUSTER_NAME}"
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
${HELM} repo add argo https://argoproj.github.io/argo-helm
${HELM} repo add openbao https://openbao.github.io/openbao-helm
${HELM} repo update jetstack metallb ingress-nginx openbao argo

install_or_skip cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true --set installCRDs=true
install_or_skip metallb metallb/metallb --namespace metallb
install_or_skip ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx

ARGOCD_HOSTNAME=argocd.local
execute_or_skip $KUBECTL create namespace ${NS_ARGOCD}

# Inject shared ca
execute_or_skip ${KUBECTL} create secret tls shared-ca \
  --namespace cert-manager --cert=$CA_CERT_FILECRT --key=$CA_CERT_FILEKEY

# Create shared-ca cluster issuer for local certificate generation
${KUBECTL} apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: shared-ca-issuer
spec:
  ca:
    secretName: shared-ca
EOF

# Let's wait for the ingress stack to be installed (required for argocd
# ingress to deploy)
${KUBECTL} wait deployment --all --for=condition=Available --timeout=60s \
   -n ingress-nginx

ARGOCD_VALUES_FILE=$TEMP_DIR/argocd-values.yaml
cat > "${ARGOCD_VALUES_FILE}" << EOF
namespaceOverride: ${NS_ARGOCD}
global:
  domain: ${ARGOCD_HOSTNAME}
  hostAliases:
  # Make openbao ingress hostname resolvable in-cluster too
  - ip: ${ADMIN_INGRESS_IP}
    hostnames:
    - ${ADMIN_INGRESS_HOSTNAME}
  - ip: ${PRODUCTION_INGRESS_IP}
    hostnames:
    - ${PRODUCTION_INGRESS_HOSTNAME}
crds:
  # Install and upgrade CRDs
  install: true
  # Drop CRDs on chart uninstall
  keep: false
server:
  certificate:
    enabled: true
    issuer:
      kind: ClusterIssuer
      name: shared-ca-issuer
  ingress:
    enabled: true
    ingressClassName: nginx
    tls: true
    annotations:
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      nginx.ingress.kubernetes.io/ssl-passthrough: "true"
      # If you encounter a redirect loop or are getting a 307 response code
      # then you need to force the nginx ingress to connect to the backend
      # using HTTPS.
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
secret:
  # htpasswd -nbBC 10 "" $ARGO_PWD | tr -d ':\n' | sed 's/$2y/$2a/
  # rootroot
  argocdServerAdminPassword: "$2a$10$nsKk.wfDSNLY3b5sOPFCAej5BPt7fboVeOjLCHPaVAZ8wqdmc8xty"
EOF

# Install argocd
ARGOCD_VERSION=9.4.1
$HELM upgrade --install argocd argo/argo-cd --values "${ARGOCD_VALUES_FILE}" \
  --namespace ${NS_ARGOCD} \
  --version ${ARGOCD_VERSION} \
  --create-namespace

${KUBECTL} wait deployment -n "${NS_ARGOCD}" --all --for=condition=Available \
  --timeout=60s

execute_or_skip ${KUBECTL} create namespace "${NS_OPENBAO}"

# Copy into bao ns
execute_or_skip ${KUBECTL} create configmap \
  --namespace "${NS_OPENBAO}" shared-ca --from-file=ca.crt=$CA_CERT_FILECRT

# Enable ingress controller load balancer IP allocation through metallb
# Let's wait for the various cogs to be installed though
${KUBECTL} wait deployment --all --for=condition=Available --timeout=60s \
   -n metallb

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
    - ${ADMIN_INGRESS_IP}/32
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

OPENBAO_VERSION=0.25.0

# Let's make argocd install openbao through an argocd application
$KUBECTL apply -f - <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: local-cluster-openbao
  namespace: ${NS_ARGOCD}
spec:
  project: default
  source:
    repoURL: https://openbao.github.io/openbao-helm
    chart: openbao
    targetRevision: v${OPENBAO_VERSION}
    helm:
      releaseName: openbao
      values: |
        injector:
          logLevel: trace
        server:
          # TODO: Use a more resilient and persistent server implementation (default token: "root")
          dev:  # in-memory
            enabled: true
          logLevel: trace
          # Add some extra dns records so we don't need an extra dns
          hostAliases:
          # Make openbao ingress hostname resolvable in-cluster too
          - ip: ${ADMIN_INGRESS_IP}
            hostnames:
            - ${ADMIN_INGRESS_HOSTNAME}
          # Enable ingress so openbao is reachable from outside the cluster too
          ingress:
            enabled: true
            ingressClassName: nginx
            hosts:
            - host: ${ADMIN_INGRESS_HOSTNAME}
            tls:
            - secretName: openbao-tls
              hosts:
              - ${ADMIN_INGRESS_HOSTNAME}
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
  destination:
    server: ${CLUSTER_URL}
    namespace: ${NS_OPENBAO}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# Wait for argocd sync window to kick in
${KUBECTL} wait deployment -n "${NS_OPENBAO}" --all --for=condition=Available \
  --timeout=60s || \
  ( echo "Waiting with argocd ns failed... " && \
    echo "Let's fallback to sleep to give some time for argocd sync window to kick in." \
    && sleep 5 )

${KUBECTL} wait deployment -n "${NS_OPENBAO}" --all --for=condition=Available \
  --timeout=60s

# Create a cluster issuer shared-ca-issuer and generate a certificate for openbao
${KUBECTL} apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: openbao-tls
  namespace: ${NS_OPENBAO}
spec:
  # will contain tls.crt & tls.key
  secretName: openbao-tls
  dnsNames:
  # FQDN that vso pods will use to communicate with openbao
  - ${ADMIN_INGRESS_HOSTNAME}
  issuerRef:
    name: shared-ca-issuer
    kind: ClusterIssuer
EOF

# Manipulate argocd to configure its password to a basic one to ease local
# manipulation
ARGOCD_ADMIN_PASS=rootroot
# ARGOCD_ADMIN_INITIAL_PWD=$($KUBECTL \
#   -n ${NS_ARGOCD} get secret argocd-initial-admin-secret \
#   -o jsonpath="{.data.password}" | base64 -d)

# Assuming the login the first time around is ok, we will update the password
# after that, we will ignore the error
# execute_or_skip \
#   argocd login ${ARGOCD_HOSTNAME} \
#     --grpc-web \
#     --insecure \
#     --username admin \
#     --password "${ARGOCD_ADMIN_INITIAL_PWD}" && \
#     execute_or_skip \
#       argocd account update-password \
#         --server ${ARGOCD_HOSTNAME} \
#         --insecure \
#         --account admin \
#         --current-password "${ARGOCD_ADMIN_INITIAL_PWD}" \
#         --new-password "${ARGOCD_ADMIN_PASS}"

cat <<EOF
##############################################
## OpenBAO cluster configured successfully! ##

Configure your local /etc/hosts to access OpenBAO instance through ingress load balancer IP
echo "${ADMIN_INGRESS_IP} ${ADMIN_INGRESS_HOSTNAME}" | sudo tee -a /etc/hosts
echo "${ADMIN_INGRESS_IP} ${ARGOCD_HOSTNAME}" | sudo tee -a /etc/hosts

Access openbao ui at: http://${ADMIN_INGRESS_HOSTNAME} -> token=${OPENBAO_DEFAULT_TOKEN}
Access argocd ui at: http://${ARGOCD_HOSTNAME} -> login/pass: admin/${ARGOCD_ADMIN_PASS}

##############################################
EOF
