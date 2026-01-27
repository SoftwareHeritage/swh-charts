#!/usr/bin/env bash

# This script configures the environment cluster for VSO deployment:
# * create `vso` and `app` namespaces
# * install vso helm chart inside `vso` namespace
# * configure vault auth from vso cluster

set -xe

TEMP_DIR=$(mktemp -d)
#trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

# To configure properly the install_or_skip function
HELM=$HELM_VSO

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

execute_or_skip ${KUBECTL_VSO} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL_VSO} create namespace "${NS_APP}"

# Inject shared ca
execute_or_skip ${KUBECTL_VSO} delete secret shared-ca --namespace "${NS_VSO}"
${KUBECTL_VSO} create secret generic shared-ca --namespace "${NS_VSO}" --from-file=ca.crt=$CA_CERT_FILECRT

VSO_VALUES_FILE=$TEMP_DIR/vso-values.yaml
cat > "${VSO_VALUES_FILE}" << EOF
controller:
  manager:
    logging:
      level:  trace
  hostAliases:
    # Make openbao ingress hostname resolvable
    - ip: ${OPENBAO_INGRESS_IP}
      hostnames:
      - ${OPENBAO_INGRESS_HOSTNAME}
defaultVaultConnection:
  enabled: true
  address: https://${OPENBAO_INGRESS_HOSTNAME}
  caCertSecret: shared-ca
EOF

# https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml
install_or_skip vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace "${NS_VSO}" \
  --values "${VSO_VALUES_FILE}"

execute_or_skip ${KUBECTL_VSO} create namespace "${NS_APP}"

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

POD_SCRIPT_FILENAME="configure-bao.sh"
POD_SCRIPT_FILE="${TEMP_DIR}/${POD_SCRIPT_FILENAME}"
cat > "${POD_SCRIPT_FILE}" << EOF
#!/usr/bin/env sh

${POD_VAULT_CMD} secrets list | grep "${MOUNT}/" || \
  ${POD_VAULT_CMD} secrets enable -path="${MOUNT}" kv-v2

${POD_VAULT_CMD} auth list | grep "${MOUNT}/" || \
  ${POD_VAULT_CMD} auth enable -path "${MOUNT}" approle

${POD_VAULT_CMD} policy write "${POLICY_NAME}" "${POD_TEMP_PATH}/${POLICY_FILENAME}"
${POD_VAULT_CMD} policy read "${POLICY_NAME}"

${POD_VAULT_CMD} write auth/${MOUNT}/role/${ROLE} \
  secret_id_ttl=0 \
  token_ttl=1h \
  token_max_ttl=4h \
  policies="${POLICY_NAME}"
EOF
chmod +x "${POD_SCRIPT_FILE}"

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

POD_NAME=$(${KUBECTL_OPENBAO} get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
POD_DEST_PATH="${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"

${KUBECTL_OPENBAO} cp "${POLICY_FILE}" "${POD_DEST_PATH}"
${KUBECTL_OPENBAO} cp "${POD_SCRIPT_FILE}" "${POD_DEST_PATH}"
${KUBECTL_OPENBAO} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"

ROLE_ID=$(${KUBECTL_OPENBAO} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
 "${POD_VAULT_CMD} read -field=role_id auth/${MOUNT}/role/${ROLE}/role-id" \
)

SECRET_ID=$(${KUBECTL_OPENBAO} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} write -field=secret_id -f auth/${MOUNT}/role/${ROLE}/secret-id"
)

ROLE_SECRET_NAME="${ROLE}-secret"

execute_or_skip ${KUBECTL_VSO} delete secret "${ROLE_SECRET_NAME}" --namespace "${NS_APP}"
${KUBECTL_VSO} create secret generic "${ROLE_SECRET_NAME}" --namespace "${NS_APP}" \
  --from-literal=id="${SECRET_ID}"

VAULT_AUTH_FILENAME="${VAULT_AUTH_NAME}.yaml"
VAULT_AUTH_FILE="${TEMP_DIR}/${VAULT_AUTH_FILENAME}"
cat > "${VAULT_AUTH_FILE}" << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${VAULT_AUTH_NAME}
  namespace: ${NS_APP}
spec:
  method: appRole
  mount: ${MOUNT}
  appRole:
    roleId: ${ROLE_ID}
    secretRef: ${ROLE_SECRET_NAME}
  allowedNamespaces:
    - "*"
EOF
${KUBECTL_VSO} apply -f "${VAULT_AUTH_FILE}"
