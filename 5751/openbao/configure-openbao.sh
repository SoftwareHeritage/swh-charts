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

CLUSTER_CONTEXT="kind-local-cluster"

HELM="helm --kube-context ${CLUSTER_CONTEXT}"
KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"

#########
## bao ##
#########

MOUNT="demo-mount"
ROLE="demo-role"
POLICY_NAME="demo-policy"
SECRET_PATH="demo-app/config"

#################
## k8s (admin) ##
#################
NS_OPENBAO="openbao"
POD_TEMP_PATH="/home/openbao"

###############################
## k8s (prod, staging, etc.) ##
###############################
# kind: Namespace
NS_VSO="vso"
NS_APP="demo-app"

# kind: ServiceAccount
SERVICE_ACCOUNT_NAME="default"

# kind: Secret
SECRET_NAME="demo-secret"

# kind: VaultStaticSecret
STATIC_SECRET_NAME="demo-static-secret"

# kind: ClusterRoleBinding
CLUSTER_ROLE_BINDING_NAME="demo-auth-delegator"

# kind: VaultAuth
VAULT_AUTH_NAME="demo-auth"

# kind: VaultConnection
VAULT_CONNECTION_NAME="demo-connection"

# TODO use ingress to allow multi-cluster access
VAULT_ADDRESS="http://chart-example.local"

################################
## Cleanup existing resources ##
################################

$HELM uninstall vault-secrets-operator || true
# $KUBECTL delete namespace ${NS_VSO} || true

$HELM uninstall openbao || true
# $KUBECTL delete namespace ${NS_OPENBAO} || true

$KUBECTL delete clusterrolebinding ${CLUSTER_ROLE_BINDING_NAME} || true

#############################
## Install openbao and vso ##
#############################

$HELM repo add openbao https://openbao.github.io/openbao-helm

# TODO configure values as needed, see https://github.com/openbao/openbao-helm/blob/main/charts/openbao/values.yaml
$HELM upgrade \
  --install openbao openbao/openbao \
  --set "server.dev.enabled=true" \
  --set "server.ingress.enabled=true" \
  --set "server.ingress.ingressClassName=nginx" \
  -n "${NS_OPENBAO}" \
  --create-namespace

# TODO configure values as needed, see https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml
$HELM upgrade \
  --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --set "controller.hostAliases[0].ip=172.18.255.0" \
  --set "controller.hostAliases[0].hostnames[0]=chart-example.local" \
  -n "${NS_VSO}" \
  --create-namespace

sleep 2

#NGINX_NODE_IP=$($KUBECTL get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
#NGINX_NODE_PORT=$($KUBECTL get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[0].nodePort}')
#echo "Access openbao ui here: http://${NGINX_NODE_IP}:${NGINX_NODE_PORT}/openbao/ui/"

POD_NAME=""
while [ -z "${POD_NAME}" ]; do
  POD_NAME=$($KUBECTL get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
  sleep 2
done

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
KUBERNETES_CA_CONTENT=$($KUBECTL config view --raw --minify --flatten --output 'jsonpath={.clusters[].cluster.certificate-authority-data}')
echo "${KUBERNETES_CA_CONTENT}" | base64 --decode > "${KUBERNETES_CA_FILE}"

POD_VAULT_CMD="bao"
POD_SCRIPT_FILENAME="configure-bao.sh"
POD_SCRIPT_FILE="${TEMP_DIR}/${POD_SCRIPT_FILENAME}"
cat > "${POD_SCRIPT_FILE}" << EOF
#!/usr/bin/env sh

${POD_VAULT_CMD} secrets enable -path="${MOUNT}" kv-v2
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

# sleep until container is ready
$KUBECTL wait --for=condition=Ready pod/"${POD_NAME}" -n "${NS_OPENBAO}" --timeout=120s

$KUBECTL cp "${POLICY_FILE}" "${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL cp "${KUBERNETES_CA_FILE}" "${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL cp "${POD_SCRIPT_FILE}" "${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"

#############################################
## Create app namespace in the app cluster ##
#############################################

if ! ${KUBECTL} get namespace "${NS_APP}" > /dev/null 2>&1; then
  echo "Namespace ${NS_APP} does not exist. Creating it."
  $KUBECTL create namespace ${NS_APP}
fi

#######################################################################
## Create VaultAuth and VaultConnection in the app cluster/namespace ##
#######################################################################

VAULT_AUTH_FILENAME="${VAULT_AUTH_NAME}.yaml"
VAULT_AUTH_FILE="${TEMP_DIR}/${VAULT_AUTH_FILENAME}"
cat > "${VAULT_AUTH_FILE}" << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  namespace: ${NS_APP}
  name: ${VAULT_CONNECTION_NAME}
spec:
  address: ${VAULT_ADDRESS}
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
  vaultConnectionRef: ${VAULT_CONNECTION_NAME}
EOF

$KUBECTL apply -f "${VAULT_AUTH_FILE}"

#######################################################################
## Create VaultAuth and VaultConnection in the app cluster/namespace ##
#######################################################################

$KUBECTL create clusterrolebinding ${CLUSTER_ROLE_BINDING_NAME} \
  --clusterrole=system:auth-delegator \
  --serviceaccount=${NS_APP}:${SERVICE_ACCOUNT_NAME}

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
  path: ${SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${SECRET_NAME}
EOF
$KUBECTL apply -f "${STATIC_SECRET_FILE}"
 apply -f "${STATIC_SECRET_FILE}"
