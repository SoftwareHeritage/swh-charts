#!/usr/bin/env bash
# * add port-forwarding to pod `openbao-0`
  #    *
  #* [connect to ui](http://localhost:8200/) with token `root`
  #    * create secret into `demo-mount/demo-app/config`
  #* wait a few seconds, then look for k8s secret `demo-secret` in namespace `demo-app`, it
set -xe

# https://www.sfeir.dev/cloud/simplifier-la-gestion-des-secrets-avec-vault-secret-operator/

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

# To configure properly the install_or_skip function
HELM=$HELM_OPENBAO
KUBECTL=$KUBECTL_OPENBAO

execute_or_skip ${KUBECTL} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL} create namespace "${NS_APP}"

# If --cleanup is set, remove existing resources
if [[ "$1" == "--cleanup" ]]; then
  # execute_or_skip $KUBECTL delete VaultAuth "${VAULT_AUTH_NAME}" \
  #   --namespace "${NS_APP}"
  # execute_or_skip $KUBECTL delete VaultStaticSecret "${STATIC_SECRET_NAME}" \
  #   --namespace "${NS_APP}"
  # execute_or_skip $KUBECTL delete VaultConnection default

  uninstall_or_skip vault-secret-operator --namespace "${NS_VSO}"
fi

execute_or_skip ${KUBECTL} delete secret openbao-tls -n "${NS_VSO}"
${KUBECTL} get secret openbao-tls -n "${NS_OPENBAO}" -o yaml | sed "s/namespace: ${NS_OPENBAO}/namespace: ${NS_VSO}/" | ${KUBECTL} apply -f -

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
  # address: http://openbao.openbao:8200
  caCertSecret: openbao-tls
  skipTLSVerified: false
EOF

install_or_skip vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace "${NS_VSO}" \
  --values "${VSO_VALUES_FILE}"

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_VSO}"

POD_NAME=$($KUBECTL_OPENBAO get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

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
KUBERNETES_CA_CONTENT=$(${KUBECTL} get secret openbao-tls -n "${NS_OPENBAO}" \
  -o jsonpath="{.data['tls\.crt']}" | base64 --decode)
echo "${KUBERNETES_CA_CONTENT}" > "${KUBERNETES_CA_FILE}"

POD_SCRIPT_FILENAME="configure-bao.sh"
POD_SCRIPT_FILE="${TEMP_DIR}/${POD_SCRIPT_FILENAME}"
cat > "${POD_SCRIPT_FILE}" << EOF
#!/usr/bin/env sh

${POD_VAULT_CMD} secrets list | grep "${MOUNT}/" || \
  ${POD_VAULT_CMD} secrets enable -path="${MOUNT}" kv-v2

${POD_VAULT_CMD} auth list | grep "${MOUNT}/" || \
  ${POD_VAULT_CMD} auth enable -path "${MOUNT}" kubernetes

${POD_VAULT_CMD} write "auth/${MOUNT}/config" \
  kubernetes_host="https://${OPENBAO_INGRESS_HOSTNAME}" \
  kubernetes_ca_cert=@"${POD_TEMP_PATH}/${KUBERNETES_CA_FILENAME}" \
  disable_issuer_verification=true \
  disable_local_ca_jwt=true

echo "### Mounted Vault Kubernetes auth config:"
${POD_VAULT_CMD} read "auth/${MOUNT}/config"
echo "#########################################"

${POD_VAULT_CMD} policy write "${POLICY_NAME}" "${POD_TEMP_PATH}/${POLICY_FILENAME}"

echo "### Created Vault policy:"
${POD_VAULT_CMD} policy read "${POLICY_NAME}"
echo "#########################"

${POD_VAULT_CMD} write "auth/${MOUNT}/role/${ROLE}" \
  bound_service_account_names="*" \
  bound_service_account_namespaces="*" \
  policies="${POLICY_NAME}"

echo "### Created Vault Kubernetes auth role:"
${POD_VAULT_CMD} read "auth/${MOUNT}/role/${ROLE}"
echo "#######################################"

EOF
chmod +x "${POD_SCRIPT_FILE}"

# sleep until container is ready
$KUBECTL wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

$KUBECTL cp "${POLICY_FILE}" "${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL cp "${KUBERNETES_CA_FILE}" "${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL cp "${POD_SCRIPT_FILE}" "${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"

#######################################################################
## Create VaultAuth and VaultConnection in the app cluster/namespace ##
#######################################################################

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
  method: kubernetes
  mount: ${MOUNT}
  kubernetes:
    role: ${ROLE}
    serviceAccount: ${SERVICE_ACCOUNT_NAME}
  allowedNamespaces:
    - "*"
EOF

$KUBECTL apply -f "${VAULT_AUTH_FILE}"

#######################################################################
## Create VaultAuth and VaultConnection in the app cluster/namespace ##
#######################################################################

execute_or_skip $KUBECTL create clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" \
  --clusterrole="system:${CLUSTER_ROLE_BINDING_NAME}" \
  --serviceaccount="${NS_APP}:${SERVICE_ACCOUNT_NAME}"

###########################################################
## Create VaultStaticSecret in the app cluster/namespace ##
###########################################################

STATIC_SECRET_FILENAME="${STATIC_SECRET_NAME}.yaml"
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
$KUBECTL apply -f "${STATIC_SECRET_FILE}"

# Write a secret password
$KUBECTL exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_VAULT_CMD} \
  kv put -mount=${MOUNT} ${OPENBAO_SECRET_PATH} username='demo-user' password='demo-pass'"

# for now, let's wait for sync
sleep 10

$KUBECTL get secret "${K8S_SECRET_NAME}" -n "${NS_APP}" -o json | \
    jq -r '.data._raw' | base64 --decode | jq '.data'
