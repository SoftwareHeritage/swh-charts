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

STATIC_SECRET_FILE="${TEMP_DIR}/${STATIC_SECRET_FILENAME}"
cat > "${STATIC_SECRET_FILE}" << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: ${STATIC_SECRET_NAME}
  namespace: ${NS_APP}
spec:
  vaultAuthRef: ${VAULT_AUTH_NAME}
  mount: ${MOUNT}
  type: kv-v2
  path: ${OPENBAO_SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${K8S_SECRET_NAME}
EOF
${KUBECTL_VSO} apply -f "${STATIC_SECRET_FILE}"

# Let's create a secret in the vso cluster

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"
POD_NAME=$($KUBECTL_OPENBAO get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

# Write a secret password
$KUBECTL_OPENBAO exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_VAULT_CMD} kv put -mount=${MOUNT} ${OPENBAO_SECRET_PATH} username='demo-user' password='demo-pass'"

# for nowbao
sleep 30

$KUBECTL_VSO get secret "${K8S_SECRET_NAME}" -n "${NS_APP}" -o json | \
    jq -r '.data._raw' | base64 --decode | jq '.data'
