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
  echo -e "\nConfigure secret synchronization, creates an openbao secret and checks "
  echo -e "\nthat new secret is stored in the kubernetes cluster\n"
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

echo "### Synchronization with authorized mount path should be ok ###"

echo "Write a secret in openbao in authorized (in openbao policy) mount path <$MOUNT>."
echo "This secret should be synchronized correctly in cluster <$CLUSTER_NAME>."

$KUBECTL_ADMIN wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"
POD_NAME=$($KUBECTL_ADMIN get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

$KUBECTL_ADMIN exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} kv put -mount=${MOUNT} ${OPENBAO_SECRET_PATH} username='demo-user' password='demo-pass'"

echo "1. First, create a VaultStaticSecret to define the secret to synchronize in vso."

$KUBECTL apply -f - <<EOF
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

echo "2. Check the secret is synchronized correctly in the cluster <$CLUSTER_NAME>."

echo "Waiting for the synchronization to be ok"
timeout 20s bash -c "until $KUBECTL get secret $K8S_SECRET_NAME --namespace=$NS_APP &>/dev/null; do printf \".\"; sleep 0.2; done"

[ $? -ne 0 ] && echo "ohoh! We did not find the secret, check your setup!" && exit 1

SECRET=$(${KUBECTL} get secret ${K8S_SECRET_NAME} --namespace=${NS_APP})
echo "Secret: $SECRET"

echo "### Synchronization with authorized mount path IS ok! ###"
echo

echo "### Synchronization with unauthorized mount path should be unauthorized access."

echo "1. First, create a VaultStaticSecret to define the secret to synchronize."

$KUBECTL apply -f - <<EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: ${UNAUTHORIZED_STATIC_SECRET_NAME}
  namespace: ${NS_APP}
spec:
  vaultAuthRef: ${VAULT_AUTH_NAME}
  mount: ${UNAUTHORIZED_MOUNT}
  type: kv-v2
  path: ${OPENBAO_SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${UNAUTHORIZED_K8S_SECRET_NAME}
EOF

echo "2. Try to synchronize that secret from unauthorized mount point"
( $KUBECTL get secret $UNAUTHORIZED_K8S_SECRET_NAME --namespace=$NS_APP 2>&1 | \
  grep -iq "not found" && \
  echo "Expectedly the secret <$UNAUTHORIZED_K8S_SECRET_NAME> does not exist.") || \
  ( echo "uhoh! The secret <$UNAUTHORIZED_K8S_SECRET_NAME> exist, it should not." && \
    exit 2 )

( $KUBECTL describe VaultStaticSecret -n $NS_APP | \
  grep -iq "permission denied\|403" && \
  echo "Expectedly the VaultStaticSecret <${UNAUTHORIZED_STATIC_SECRET_NAME}> is denied access by openbao." ) || \
  ( echo "uhoh! The VaultStaticSecret <${UNAUTHORIZED_STATIC_SECRET_NAME}> got granted access!" && \
    exit 2 )

echo "### Synchronization with unauthorized mount path IS indeed unauthorized access! ###"
