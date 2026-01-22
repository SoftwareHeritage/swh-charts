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

# To configure properly the install_or_skip function
HELM=$HELM_OPENBAO

execute_or_skip ${KUBECTL_OPENBAO} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL_OPENBAO} create namespace "${NS_APP}"

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
  caCertSecret: vso-tls-secret
EOF

# TODO configure values as needed, see
# https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml
install_or_skip vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace "${NS_VSO}" \
  --values "${VSO_VALUES_FILE}"

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_VSO}"

VAULT_AUTH_NAME="auth-${CLUSTER_NAME_VSO}"

MOUNT="mount-${CLUSTER_NAME_VSO}"
POLICY_NAME="policy-${CLUSTER_NAME_VSO}"
CLUSTER_ROLE_BINDING_NAME="auth-delegator"

VAULT_AUTH_FILENAME="${VAULT_AUTH_NAME}.yaml"
VAULT_AUTH_FILE="${TEMP_DIR}/${VAULT_AUTH_FILENAME}"
cat > "${VAULT_AUTH_FILE}" << EOF
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
  allowedNamespaces:
    - "*"
EOF

execute_or_skip ${KUBECTL_OPENBAO} create namespace "${NS_APP}"

${KUBECTL_OPENBAO} apply -f "${VAULT_AUTH_FILE}"
execute_or_skip ${KUBECTL_OPENBAO} create clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" \
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
execute_or_skip ${KUBECTL_OPENBAO} delete secret "${SERVICE_ACCOUNT_NAME_SECRET}" -n "${NS_APP}"

${KUBECTL_OPENBAO} apply -f - <<EOF
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

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n ingress-nginx

${KUBECTL_OPENBAO} apply -f - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubeapi
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
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
              number: 80
  tls:
  - hosts:
    - "${VSO_INGRESS_HOSTNAME}"
    secretName: vso-tls-secret
EOF

#VSO_TLS_CA_CRT_FILE="${TEMP_DIR}/vso-ca.crt"
#${KUBECTL_OPENBAO} get secret vso-tls-secret -o jsonpath="{.data['ca\.crt']}" | base64 --decode > "${VSO_TLS_CA_CRT_FILE}"
#
#VSO_TLS_CRT_FILE="${TEMP_DIR}/vso-tls.crt"
#${KUBECTL_OPENBAO} get secret vso-tls-secret -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "${VSO_TLS_CRT_FILE}"
#
#VSO_TLS_KEY_FILE="${TEMP_DIR}/vso-tls.key"
#${KUBECTL_OPENBAO} get secret vso-tls-secret -o jsonpath="{.data['tls\.key']}" | base64 --decode > "${VSO_TLS_KEY_FILE}"
#
#${KUBECTL_OPENBAO} create token "${SERVICE_ACCOUNT_NAME}" --namespace "${NS_APP}" \
#  --bound-object-kind Secret \
#  --bound-object-name default-secret \
#  --certificate-authority "${VSO_TLS_CA_CRT_FILE}" \
#  --client-certificate "${VSO_TLS_CRT_FILE}" \
#  --client-key "${VSO_TLS_KEY_FILE}"
#
#echo "Stop now"
#exit 1

TLS_CRT_FILENAME="tls.crt"
TLS_CRT_FILE="${TEMP_DIR}/${TLS_CRT_FILENAME}"

CA_CRT_FILENAME="ca.crt"
CA_CRT_FILE="${TEMP_DIR}/${CA_CRT_FILENAME}"

${KUBECTL_OPENBAO} get secret vso-tls-secret -o jsonpath="{.data['tls\.crt']}" | base64 --decode | tee "${TLS_CRT_FILE}"
echo "TLS_CRT_FILE: $(cat ${TLS_CRT_FILE})"

${KUBECTL_OPENBAO} get secret "${SERVICE_ACCOUNT_NAME_SECRET}" -n "${NS_APP}" -o jsonpath="{.data['ca\.crt']}" | base64 --decode | tee "${CA_CRT_FILE}"
echo "CA_CRT_FILE: $(cat ${CA_CRT_FILE})"

SA_TOKEN=$(${KUBECTL_OPENBAO} get secret "${SERVICE_ACCOUNT_NAME_SECRET}" -n "${NS_APP}" -o jsonpath="{.data.token}")
echo "SA_TOKEN: ${SA_TOKEN}"

SA_TOKEN_DECODED=$(echo "${SA_TOKEN}" | base64 --decode)
echo "SA_TOKEN_DECODED: ${SA_TOKEN_DECODED}"

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
  token_reviewer_jwt="${SA_TOKEN_DECODED}" \
  kubernetes_host="https://${VSO_INGRESS_HOSTNAME}:${VSO_INGRESS_PORT}" \
  kubernetes_ca_cert=@"${POD_TEMP_PATH}/${TLS_CRT_FILENAME}" \
  pem_keys=@"${POD_TEMP_PATH}/${CA_CRT_FILENAME}"
#  -ca-cert
#  -client-cert
#  -client-key

echo "### Mounted Vault Kubernetes auth config:"
${POD_VAULT_CMD} read "auth/${MOUNT}/config"
echo "#########################################"

${POD_VAULT_CMD} policy write "${POLICY_NAME}" "${POD_TEMP_PATH}/${POLICY_FILENAME}"

echo "### Created Vault policy:"
${POD_VAULT_CMD} policy read "${POLICY_NAME}"
echo "#########################"

${POD_VAULT_CMD} write "auth/${MOUNT}/role/${ROLE}" \
  bound_service_account_names="${SERVICE_ACCOUNT_NAME}" \
  bound_service_account_namespaces="${NS_APP}" \
  policies="${POLICY_NAME}"

echo "### Created Vault Kubernetes auth role:"
${POD_VAULT_CMD} read "auth/${MOUNT}/role/${ROLE}"
echo "#######################################"
EOF
chmod +x "${POD_SCRIPT_FILE}"

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

POD_NAME=$(${KUBECTL_OPENBAO} get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
POD_DEST_PATH="${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"

${KUBECTL_OPENBAO} cp "${POLICY_FILE}" "${POD_DEST_PATH}"
${KUBECTL_OPENBAO} cp "${TLS_CRT_FILE}" "${POD_DEST_PATH}"
${KUBECTL_OPENBAO} cp "${CA_CRT_FILE}" "${POD_DEST_PATH}"
${KUBECTL_OPENBAO} cp "${POD_SCRIPT_FILE}" "${POD_DEST_PATH}"
${KUBECTL_OPENBAO} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"


VAULT_AUTH_NAME="auth-${CLUSTER_NAME_OPENBAO}"

STATIC_SECRET_NAME="demo-static-secret"
OPENBAO_SECRET_PATH="demo-app/config"
K8S_SECRET_NAME="demo-secret"

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
  vaultAuthRef: ${VAULT_AUTH_NAME}
  mount: ${MOUNT}
  type: kv-v2
  path: ${OPENBAO_SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${K8S_SECRET_NAME}
EOF
${KUBECTL_OPENBAO} apply -f "${STATIC_SECRET_FILE}"

# Let's create a secret in the vso cluster

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"
POD_NAME=$(${KUBECTL_OPENBAO} get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

# Write a secret password
${KUBECTL_OPENBAO} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_VAULT_CMD} kv put -mount=${MOUNT} ${OPENBAO_SECRET_PATH} username='demo-user' password='demo-pass'"

# for nowbao
sleep 10

${KUBECTL_OPENBAO} get secret "${K8S_SECRET_NAME}" -n "${NS_APP}" -o json | \
    jq -r '.data._raw' | base64 --decode | jq '.data'
