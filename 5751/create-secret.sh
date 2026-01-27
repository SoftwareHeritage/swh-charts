#!/usr/bin/env bash
# -*- eval: (setq-default sh-indentation 2) -*-

# This script creates a new vault secret, and synchronises it to the target environment cluster secret:
# * create a VaultStaticSecret
# *
# * wait for the secret to be synchronised to the target k8s secret

set -e

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

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

CLUSTER_NAME=$1
shift

# Display help message
usage() {
  echo "Usage: $0 CLUSTER_NAME [OPTIONS]"
  echo -e "\nCreates an openbao secret and configure secret synchronization\n"
  echo "Options:"
  echo "  --debug     Enable verbose instructions"
  echo "  -h, --help  Display this help message"
  exit 1
}

if [ -z "${CLUSTER_NAME}" -o "${CLUSTER_NAME}" = "-h" -o "${CLUSTER_NAME}" = "--help" ]; then
  echo "Error: Targeted cluster name is mandatory."
  usage
  exit 1
fi

set_variables_for_cluster ${CLUSTER_NAME}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      set -x
      shift
      ;;
    -h|--help)
      usage
      shift
      ;;
  esac
done

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
${KUBECTL} apply -f "${STATIC_SECRET_FILE}"

# Let's create a secret in the vso cluster

${KUBECTL_ADMIN} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"
POD_NAME=$($KUBECTL_ADMIN get pods -n "${NS_OPENBAO}" \
  -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

# Write a secret password
$KUBECTL_ADMIN exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} kv put -mount=${MOUNT} ${OPENBAO_SECRET_PATH} username='demo-user' password='demo-pass'"

secret=
DURATION=10
START_TIME=$(date +%s)

while [[ $(($(date +%s) - START_TIME)) -lt $DURATION ]]; do
  secret=$($KUBECTL get secret "${K8S_SECRET_NAME}" -n "${NS_APP}" -o json | \
             jq -r '.data._raw' | base64 --decode | jq '.data')
  if [ ! -z "$secret" ]; then
    echo "Secret found in targeted cluster <$CLUSTER_NAME>"
    echo "$secret"
    exit 0
  else
    sleep 1;
  fi
done

exit 1
