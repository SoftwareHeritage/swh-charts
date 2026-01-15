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

if [[ "$1" == "--reset" ]]; then
  WITH_INGRESS="false"
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_VSO}"
  "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT_VSO}" kind "${WITH_INGRESS}"
elif [[ "$1" == "--cleanup" ]]; then
  # If --cleanup is set, remove existing resources
  $HELM_VSO uninstall vault-secrets-operator || true
#  $KUBECTL_VSO delete namespace "${NS_VSO}" || true
fi

# TODO configure values as needed, see https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml
$HELM_VSO upgrade \
  --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --set "controller.hostAliases[0].ip=${OPENBAO_INGRESS_IP}" \
  --set "controller.hostAliases[0].hostnames[0]=${OPENBAO_INGRESS_HOSTNAME}" \
  -n "${NS_VSO}" \
  --create-namespace

VAULT_AUTH_NAME="auth-${CLUSTER_NAME_VSO}"
VAULT_CONNECTION_NAME="connection-${CLUSTER_NAME_VSO}"

MOUNT="mount-${CLUSTER_NAME_VSO}"
POLICY_NAME="policy-${CLUSTER_NAME_VSO}"
ROLE="role-${CLUSTER_NAME_VSO}"
SERVICE_ACCOUNT_NAME="default"
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
  namespace: ${NS_VSO}
  name: ${VAULT_AUTH_NAME}
spec:
  method: kubernetes
  mount: ${MOUNT}
  kubernetes:
    role: ${ROLE}
    serviceAccount: ${SERVICE_ACCOUNT_NAME}
  vaultConnectionRef: ${VAULT_CONNECTION_NAME}
  allowedNamespaces:
    - "*"
EOF

$KUBECTL_VSO apply -f "${VAULT_AUTH_FILE}"
$KUBECTL_VSO get clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" > /dev/null 2>&1 || \
  $KUBECTL_VSO create clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" \
    --clusterrole=system:auth-delegator \
    --serviceaccount="${NS_VSO}:${SERVICE_ACCOUNT_NAME}"

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

KUBERNETES_CA_FILENAME="demo-ca.crt"
KUBERNETES_CA_FILE="${TEMP_DIR}/${KUBERNETES_CA_FILENAME}"
KUBERNETES_CA_CONTENT=$($KUBECTL_OPENBAO config view --raw --minify --flatten --output 'jsonpath={.clusters[].cluster.certificate-authority-data}')
echo "${KUBERNETES_CA_CONTENT}" | base64 --decode > "${KUBERNETES_CA_FILE}"

POD_VAULT_CMD="bao"
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
CA_CRT_CONTENT=\$(sed ':a;N;$!ba;s/\n/\\n/g' "${POD_TEMP_PATH}/${KUBERNETES_CA_FILENAME}")

${POD_VAULT_CMD} write "auth/${MOUNT}/config" \
  kubernetes_host="https://\${KUBERNETES_PORT_443_TCP_ADDR}:443" \
  kubernetes_ca_cert="\${CA_CRT_CONTENT}"\
  disable_local_ca_jwt='true'

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
