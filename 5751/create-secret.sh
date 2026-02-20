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

function _title {
  msg=$1
  status=$2

  args=()
  if [ ! -z "${status}" ]; then
    args=("${status}: ")
  fi

  echo -e "\n### ${args[@]}${msg} ###\n"
}

prefix_msg="1. Synchronization with authorized mount path"
_title "${prefix_msg} should be ok"

echo "- Write a secret in openbao in authorized (in openbao policy) mount path <$MOUNT>."
echo "- This secret should be synchronized correctly in cluster <$CLUSTER_NAME>."

$KUBECTL_ADMIN wait pod openbao-0 --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"
POD_NAME=$($KUBECTL_ADMIN get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

$KUBECTL_ADMIN exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} kv put -mount=${MOUNT} ${OPENBAO_SECRET_PATH} username='demo-user' password='demo-pass'"

echo "- Create a VaultStaticSecret to define the secret to synchronize in vso."

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

echo "- Secondly, check secret is synchronized correctly in cluster <$CLUSTER_NAME>."

echo "- Waiting for the synchronization to be ok"
timeout 20s bash -c "until $KUBECTL get secret $K8S_SECRET_NAME --namespace=$NS_APP &>/dev/null; do printf \".\"; sleep 0.2; done"

[ $? -ne 0 ] && echo "uhoh! We did not find the secret, check your setup!" && \
  _title "${prefix_msg} failed" "FAILURE" && exit 1

SECRET=$(${KUBECTL} get secret ${K8S_SECRET_NAME} --namespace=${NS_APP})
echo "Secret: $SECRET"

_title "${prefix_msg} is OK!" "SUCCESS"

prefix_msg="2. Synchronization with unauthorized mount path"
_title "${prefix_msg} should result in unauthorized access."

echo "- First, create a VaultStaticSecret to define the secret to synchronize."

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

echo "- Try to synchronize that secret from unauthorized mount point"
( $KUBECTL get secret $UNAUTHORIZED_K8S_SECRET_NAME --namespace=$NS_APP 2>&1 | \
  grep -iq "not found" && \
  echo "Expectedly the secret <$UNAUTHORIZED_K8S_SECRET_NAME> does not exist.") || \
  ( echo "uhoh! The secret <$UNAUTHORIZED_K8S_SECRET_NAME> exist, it should not." && \
    _title "${prefix_msg} is authorized access while it should not!" "FAILURE"
    exit 2 )

( $KUBECTL describe VaultStaticSecret -n $NS_APP | \
  grep -iq "permission denied\|403" && \
  echo "Expectedly the VaultStaticSecret <${UNAUTHORIZED_STATIC_SECRET_NAME}> is denied access by openbao." ) || \
  ( echo "uhoh! The VaultStaticSecret <${UNAUTHORIZED_STATIC_SECRET_NAME}> got granted access!" && \
    _title "${prefix_msg} is authorized access while it should not!" "FAILURE"
    exit 2 )

_title "${prefix_msg} is indeed unauthorized access!" "SUCCESS"

prefix_msg="3. Secret synchronization in another targeted namespace"
_title "${prefix_msg} should be ok"

NS_SECONDARY="app2"

echo "- First, create another namespace ${NS_SECONDARY}."

execute_or_skip ${KUBECTL} create namespace "${NS_SECONDARY}"

echo "- Then create another Vault* configuration to define sync secrets in ns <${NS_SECONDARY}>."

ROLE_ID=$(${KUBECTL_ADMIN} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
 "${POD_VAULT_CMD} read -field=role_id auth/${MOUNT}/role/${ROLE}/role-id" \
)
SECRET_ID=$(${KUBECTL_ADMIN} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c \
  "${POD_VAULT_CMD} write -field=secret_id -f auth/${MOUNT}/role/${ROLE}/secret-id"
)
ROLE_SECRET_NAME="${ROLE}-secret"

execute_or_skip ${KUBECTL} delete secret "${ROLE_SECRET_NAME}" --namespace "${NS_SECONDARY}"
${KUBECTL} create secret generic "${ROLE_SECRET_NAME}" --namespace "${NS_SECONDARY}" \
  --from-literal=id="${SECRET_ID}"

$KUBECTL apply -f - <<EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${VAULT_AUTH_NAME}
  namespace: ${NS_SECONDARY}
spec:
  method: appRole
  mount: ${MOUNT}
  appRole:
    roleId: ${ROLE_ID}
    secretRef: ${ROLE_SECRET_NAME}
  allowedNamespaces:
    - "*"
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: ${STATIC_SECRET_NAME}
  namespace: ${NS_SECONDARY}
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

echo "- Check the secret synchronizes correctly in the cluster <$CLUSTER_NAME>."

echo "- Waiting for the synchronization to be ok"
timeout 20s bash -c "until $KUBECTL get secret $K8S_SECRET_NAME --namespace=$NS_SECONDARY &>/dev/null; do printf \".\"; sleep 0.2; done"

[ $? -ne 0 ] && echo "uhoh! We did not find the secret, check your setup!" && \
  _title "${prefix_msg} did not work" "FAILURE" && exit 1

SECRET=$(${KUBECTL} get secret ${K8S_SECRET_NAME} --namespace=${NS_APP})
echo "Secret: $SECRET"

_title "${prefix_msg} is ok" "SUCCESS"

prefix_msg="4. Secret synchronization in another targeted namespace with same VaultAuth"
_title "${prefix_msg} should be ok"
echo "- Then create another Vault* configuration to define sync secrets in ns <${NS_SECONDARY}>."

STATIC_SECRET_NAME2="demo2-static-secret"
K8S_SECRET_NAME2="demo2-secret"

$KUBECTL apply -f - <<EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: ${STATIC_SECRET_NAME2}
  namespace: ${NS_SECONDARY}
spec:
  vaultAuthRef: ${NS_APP}/${VAULT_AUTH_NAME}
  mount: ${MOUNT}
  type: kv-v2
  path: ${OPENBAO_SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${K8S_SECRET_NAME2}
EOF

echo "- Check the secret synchronizes correctly in the cluster <$CLUSTER_NAME>."

echo "- Waiting for the synchronization to be ok"
timeout 20s bash -c "until $KUBECTL get secret $K8S_SECRET_NAME --namespace=$NS_SECONDARY &>/dev/null; do printf \".\"; sleep 0.2; done"

[ $? -ne 0 ] && echo "uhoh! We did not find the secret, check your setup!" && \
  _title "${prefix_msg} did not work" "FAILURE" && exit 1

SECRET=$(${KUBECTL} get secret ${K8S_SECRET_NAME} --namespace=${NS_APP})
echo "Secret: $SECRET"

_title "${prefix_msg} is ok" "SUCCESS"
