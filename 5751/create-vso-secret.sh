#!/usr/bin/env bash

# This script creates a new vault secret, and synchronises it to the target environment cluster secret:
# * create a VaultStaticSecret
# *
# * wait for the secret to be synchronised to the target k8s secret

set -xe

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

VAULT_AUTH_NAME="auth-${CLUSTER_NAME_VSO}"
MOUNT="mount-${CLUSTER_NAME_VSO}"

STATIC_SECRET_NAME="demo-static-secret"
OPENBAO_SECRET_PATH="demo-app/config"
K8S_SECRET_NAME="demo-secret"

${KUBECTL_VSO} get namespace "${NS_APP}" || \
  ${KUBECTL_VSO} create namespace "${NS_APP}"

STATIC_SECRET_FILENAME="${STATIC_SECRET_NAME}.yaml"
STATIC_SECRET_FILE="${TEMP_DIR}/${STATIC_SECRET_FILENAME}"
cat > "${STATIC_SECRET_FILE}" << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  namespace: ${NS_APP}
  name: ${STATIC_SECRET_NAME}
spec:
  vaultAuthRef: ${NS_VSO}/${VAULT_AUTH_NAME}
  mount: ${MOUNT}
  type: kv-v2
  path: ${OPENBAO_SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${K8S_SECRET_NAME}
EOF
${KUBECTL_VSO} apply -f "${STATIC_SECRET_FILE}"
