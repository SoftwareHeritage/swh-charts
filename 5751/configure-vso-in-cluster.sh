#!/usr/bin/env bash
# -*- eval: (setq-default sh-indentation 2) -*-

# This script configures the targeted local cluster with vault-secrets-operator:
# * create `vso` and `app` namespaces
# * install vso helm chart inside `vso` namespace
# * configure vault auth from the targeted cluster in the openbao cluster

# This script does not create any secrets yet (see create-secret.sh)

set -e

TEMP_DIR=$(mktemp -d)
#trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
  source "${SCRIPT_DIR}/.helper-functions.sh"
else
  echo "<${ENV_FILE}> is required, failing."
  exit 1
fi

DESCRIPTION="Configure the vault-secret-operator in targeted CLUSTER_NAME"

CLUSTER_NAME=$1
shift

if [ -z "${CLUSTER_NAME}" -o "${CLUSTER_NAME}" = "-h" -o "${CLUSTER_NAME}" = "--help" ]; then
  echo "Error: Targeted cluster name is mandatory."
  script_usage "${DESCRIPTION}"
  exit 1
fi

set_variables_for_cluster ${CLUSTER_NAME}
DEBUG_INSTRUCTIONS=

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

execute_or_skip ${KUBECTL} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL} create namespace "${NS_APP}"

# Inject shared ca
execute_or_skip ${KUBECTL} delete secret shared-ca --namespace "${NS_VSO}"
${KUBECTL} create secret generic shared-ca --namespace "${NS_VSO}" \
           --from-file=ca.crt=$CA_CERT_FILECRT

VSO_VALUES_FILE=$TEMP_DIR/vso-values.yaml
cat > "${VSO_VALUES_FILE}" << EOF
controller:
  manager:
    logging:
      level: trace
  hostAliases:
    # Make openbao ingress hostname resolvable
    - ip: ${ADMIN_INGRESS_IP}
      hostnames:
      - ${ADMIN_INGRESS_HOSTNAME}
defaultVaultConnection:
  enabled: true
  address: https://${ADMIN_INGRESS_HOSTNAME}
  caCertSecret: shared-ca
EOF

# https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml
install_or_skip vault-secrets-operator hashicorp/vault-secrets-operator \
                --namespace "${NS_VSO}" \
                --values "${VSO_VALUES_FILE}"

execute_or_skip ${KUBECTL} create namespace "${NS_APP}"

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

${KUBECTL_ADMIN} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

POD_NAME=$(${KUBECTL_ADMIN} get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
POD_DEST_PATH="${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"

${KUBECTL_ADMIN} cp "${POLICY_FILE}" "${POD_DEST_PATH}"
${KUBECTL_ADMIN} cp "${POD_SCRIPT_FILE}" "${POD_DEST_PATH}"
${KUBECTL_ADMIN} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"

ROLE_ID=$(${KUBECTL_ADMIN} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} read -field=role_id auth/${MOUNT}/role/${ROLE}/role-id" \
)

SECRET_ID=$(${KUBECTL_ADMIN} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} write -field=secret_id -f auth/${MOUNT}/role/${ROLE}/secret-id"
)

ROLE_SECRET_NAME="${ROLE}-secret"

execute_or_skip ${KUBECTL} delete secret "${ROLE_SECRET_NAME}" --namespace "${NS_APP}"
${KUBECTL} create secret generic "${ROLE_SECRET_NAME}" --namespace "${NS_APP}" \
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
${KUBECTL} apply -f "${VAULT_AUTH_FILE}"
