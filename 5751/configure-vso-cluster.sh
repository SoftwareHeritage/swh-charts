#!/usr/bin/env bash

# This script configures the environment cluster for VSO deployment:
# * create `vso` and `app` namespaces
# * install vso helm chart inside `vso` namespace
# * configure vault auth from vso cluster

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

if [[ "$1" == "--delete" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_VSO}"
  exit 0
elif [[ "$1" == "--reset" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_VSO}"
  "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT_VSO}" kind "true" 8080 8443
elif [[ "$1" == "--cleanup" ]]; then
  # If --cleanup is set, remove existing resources
  ${HELM_VSO} uninstall vault-secrets-operator || true
#  ${KUBECTL_VSO} delete namespace "${NS_VSO}" || true
fi

${HELM_VSO} repo add jetstack https://charts.jetstack.io
${HELM_VSO} repo add metallb https://metallb.github.io/metallb
${HELM_VSO} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
${HELM_VSO} repo update jetstack metallb ingress-nginx

${HELM_VSO} install cert-manager jetstack/cert-manager \
  --namespace "cert-manager" --create-namespace \
  --set crds.enabled=true \
  --set installCRDs=true \
  --set "hostAliases[0].ip=${VSO_INGRESS_IP}" \
  --set "hostAliases[0].hostnames[0]=${VSO_INGRESS_HOSTNAME}" \
  > /dev/null 2>&1 || echo "<cert-manager> already installed!"
${HELM_VSO} install metallb metallb/metallb --namespace metallb --create-namespace > /dev/null 2>&1 || echo "<metallb> already installed!"
${HELM_VSO} install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace > /dev/null 2>&1 || echo "<ingress-nginx> already installed!"

# Enable ingress controller load balancer IP allocation through metallb
${KUBECTL_VSO} wait pod --all --for=condition=Ready --timeout=60s -n metallb

${KUBECTL_VSO} apply -f - <<EOF
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: "local-metallb-pool-ingress"
  namespace: metallb
spec:
  addresses:
    - ${VSO_INGRESS_IP}/32
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


# TODO configure values as needed, see https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml
${HELM_VSO} upgrade \
  --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --set "controller.manager.logging.level=trace" \
  --set "controller.hostAliases[0].ip=${OPENBAO_INGRESS_IP}" \
  --set "controller.hostAliases[0].hostnames[0]=${OPENBAO_INGRESS_HOSTNAME}" \
  -n "${NS_VSO}" \
  --create-namespace

VAULT_AUTH_NAME="auth-${CLUSTER_NAME_VSO}"
VAULT_CONNECTION_NAME="connection-${CLUSTER_NAME_VSO}"

MOUNT="mount-${CLUSTER_NAME_VSO}"
POLICY_NAME="policy-${CLUSTER_NAME_VSO}"
CLUSTER_ROLE_BINDING_NAME="auth-delegator"

VAULT_AUTH_FILENAME="auth-${VAULT_AUTH_NAME}.yaml"
VAULT_AUTH_FILE="${TEMP_DIR}/${VAULT_AUTH_FILENAME}"
cat > "${VAULT_AUTH_FILE}" << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  namespace: ${NS_VSO}
  name: ${VAULT_CONNECTION_NAME}
spec:
  address: http://${OPENBAO_INGRESS_HOSTNAME}
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  namespace: ${NS_APP}
  name: ${VAULT_AUTH_NAME}
spec:
  method: kubernetes
  mount: ${MOUNT}
  kubernetes:
    role: ${ROLE}
    serviceAccount: ${SERVICE_ACCOUNT_NAME}
  vaultConnectionRef: ${NS_VSO}/${VAULT_CONNECTION_NAME}
  allowedNamespaces:
    - "*"
EOF

${KUBECTL_VSO} get namespace "${NS_APP}" || \
  ${KUBECTL_VSO} create namespace "${NS_APP}"

${KUBECTL_VSO} apply -f "${VAULT_AUTH_FILE}"
${KUBECTL_VSO} get clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" > /dev/null 2>&1 || \
  ${KUBECTL_VSO} create clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" \
    --clusterrole=system:auth-delegator \
    --serviceaccount="${NS_APP}:${SERVICE_ACCOUNT_NAME}"

POLICY_FILENAME="${POLICY_NAME}.hcl"
POLICY_FILE="${TEMP_DIR}/${POLICY_FILENAME}"
cat > "${POLICY_FILE}" << EOF
path "${MOUNT}/data/*" {
  capabilities = ["list", "read"]
}

path "${MOUNT}/metadata/*" {
  capabilities = ["list", "read"]
}
EOF

# Define a service account token secret that is used by openbao to authenticate to
# Kubernetes.
SERVICE_ACCOUNT_NAME_SECRET=${SERVICE_ACCOUNT_NAME}-secret

${KUBECTL_VSO} apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SERVICE_ACCOUNT_NAME_SECRET}
  namespace: ${NS_APP}
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
    kubernetes.io/service-account.hostname: ${VSO_INGRESS_HOSTNAME}
type: kubernetes.io/service-account-token
EOF

# TODO add variables for email, pk name, etc.
${KUBECTL_VSO} apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: sysop+k8sstaging@softwareheritage.org
    profile: tlsserver
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
    - http01:
        ingress:
          ingressClassName: nginx
EOF

${KUBECTL_VSO} apply -f - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubeapi
  namespace: default
  annotations:
    # nginx.ingress.kubernetes.io/secure-backends: "true"
    # nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
    # kubernetes.io/tls-acme: "true"
    cert-manager.io/acme-challenge-type: http01
    # acme.cert-manager.io/http01-ingress-class: nginx
    acme.cert-manager.io/http01-edit-in-place: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: "${VSO_INGRESS_HOSTNAME}"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: kubernetes
            port:
              number: 443
  tls:
  - hosts:
    - "${VSO_INGRESS_HOSTNAME}"
    secretName: vso-ingress-tls
EOF

KUBERNETES_CA_FILENAME="demo-ca.crt"
KUBERNETES_CA_FILE="${TEMP_DIR}/${KUBERNETES_CA_FILENAME}"

SA_TOKEN=$(${KUBECTL_VSO} get secret ${SERVICE_ACCOUNT_NAME_SECRET} -n ${NS_APP} \
                               -o jsonpath="{.data.token}" | base64 --decode)
KUBERNETES_CA=$(${KUBECTL_VSO} get secret ${SERVICE_ACCOUNT_NAME_SECRET} -n ${NS_APP} \
                               -o jsonpath="{.data['ca\.crt']}" | base64 --decode)


echo "${KUBERNETES_CA}" > "${KUBERNETES_CA_FILE}"

POD_SCRIPT_FILENAME="configure-bao.sh"
POD_SCRIPT_FILE="${TEMP_DIR}/${POD_SCRIPT_FILENAME}"
cat > "${POD_SCRIPT_FILE}" << EOF
#!/usr/bin/env sh

${POD_VAULT_CMD} secrets list | grep "${MOUNT}/" || \
  ${POD_VAULT_CMD} secrets enable -path="${MOUNT}" kv-v2

${POD_VAULT_CMD} auth list | grep "${MOUNT}/" || \
  ${POD_VAULT_CMD} auth enable -path "${MOUNT}" kubernetes

# read CA cert content and replace line breaks with \n
# see https://openbao.org/api-docs/next/auth/kubernetes/#parameters
${POD_VAULT_CMD} write "auth/${MOUNT}/config" \
  use_annotations_as_alias_metadata=true \
  disable_local_ca_jwt=true \
  token_reviewer_jwt="${SA_TOKEN}" \
  kubernetes_host="https://${VSO_INGRESS_HOSTNAME}:${VSO_INGRESS_PORT}" \
  kubernetes_ca_cert=@"${POD_TEMP_PATH}/${KUBERNETES_CA_FILENAME}"

${POD_VAULT_CMD} policy write "${POLICY_NAME}" "${POD_TEMP_PATH}/${POLICY_FILENAME}"
${POD_VAULT_CMD} write "auth/${MOUNT}/role/${ROLE}" \
  bound_service_account_names="${SERVICE_ACCOUNT_NAME}" \
  bound_service_account_namespaces="${NS_APP}" \
  policies="${POLICY_NAME}"
EOF
chmod +x "${POD_SCRIPT_FILE}"

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"
POD_NAME=$($KUBECTL_OPENBAO get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
POD_DEST_PATH="${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"

$KUBECTL_OPENBAO cp "${POLICY_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO cp "${KUBERNETES_CA_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO cp "${POD_SCRIPT_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"
