#!/usr/bin/env bash

set -xe

# https://www.sfeir.dev/cloud/simplifier-la-gestion-des-secrets-avec-vault-secret-operator/
# https://mpoore.io/posts/2024/setting-up-vault-secrets-operator-between-kubernetes-clusters/#vault-and-vso-different-clusters

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

CLUSTER_CONTEXT="kind-local-cluster-vso"
CLUSTER_CONTEXT_OPENBAO="kind-local-cluster"

HELM="helm --kube-context ${CLUSTER_CONTEXT}"
KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"
KUBECTL_OPENBAO="kubectl --context ${CLUSTER_CONTEXT_OPENBAO}"

#########
## bao ##
#########

MOUNT="vso-dev"
ROLE="demo-role"
SECRET_PATH="demo-app/config"
POLICY_NAME="demo-policy"

#################
## k8s (admin) ##
#################
NS_OPENBAO="openbao"
POD_TEMP_PATH="/home/openbao"

###############################
## k8s (prod, staging, etc.) ##
###############################
# kind: Namespace
NS_VSO="vault-secrets-operator"
NS_APP="demo-app"

# kind: ServiceAccount
SERVICE_ACCOUNT_NAME="svc-vso-dev"

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
#$KUBECTL delete namespace ${NS_VSO} || true

#############################
## Install openbao and vso ##
#############################

# Install vault-secrets operator with the values to know where the ingress
# of the openbao runs
$HELM upgrade \
  --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --set "controller.hostAliases[0].ip=172.18.255.0" \
  --set "controller.hostAliases[0].hostnames[0]=chart-example.local" \
  -n "${NS_VSO}" \
  --create-namespace

sleep 2

OPENBAO_POD_NAME=""
while [ -z "${OPENBAO_POD_NAME}" ]; do
  OPENBAO_POD_NAME=$($KUBECTL_OPENBAO get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
  sleep 2
done

############################################
# Configure the VSO Namespace in Kubernetes
############################################

# That means:
# - namespace
# - ServiceAccount ${MOUNT} & its jwt secret
# - ClusterRoleBinding

VSO_NS_SETUP_FILENAME="${VAULT_AUTH_NAME}.yaml"
VSO_NS_SETUP_FILE="${TEMP_DIR}/${VSO_NS_SETUP_FILENAME}"
cat > "${VSO_NS_SETUP_FILE}" << EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS_VSO}
  labels:
    pod-security.kubernetes.io/enforce: "privileged"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: default
---
apiVersion: v1
kind: Secret
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: default
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: ${SERVICE_ACCOUNT_NAME}
    namespace: default
EOF

$KUBECTL apply -f "${VSO_NS_SETUP_FILE}"


#############################################
## Create app namespace in the app cluster ##
#############################################

if ! ${KUBECTL} get namespace "${NS_APP}" > /dev/null 2>&1; then
  echo "Namespace ${NS_APP} does not exist. Creating it."
  $KUBECTL create namespace ${NS_APP}
fi

POD_VAULT_CMD="bao"
POD_SCRIPT_FILENAME="configure-vso.sh"
POD_SCRIPT_FILE="${TEMP_DIR}/${POD_SCRIPT_FILENAME}"

# Create the necessary configuration in openbao to allow the connection
# from the vso cluster to openbao cluster

KUBERNETES_CA_FILENAME="demo-ca.crt"
KUBERNETES_CA_FILE="${TEMP_DIR}/${KUBERNETES_CA_FILENAME}"
KUBERNETES_CA_CONTENT=$($KUBECTL config view --raw --minify --flatten --output 'jsonpath={.clusters[].cluster.certificate-authority-data}')
echo "${KUBERNETES_CA_CONTENT}" | base64 --decode > "${KUBERNETES_CA_FILE}"

TOKEN_REVIEW_JWT=$($KUBECTL get secret ${SERVICE_ACCOUNT_NAME} --output='go-template={{ .data.token }}' | base64 --decode)
KUBE_HOST=$($KUBECTL config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.server}')

cat > "${POD_SCRIPT_FILE}" << EOF
#!/usr/bin/env sh

KUBE_CA_CERT=\$(sed ':a;N;$!ba;s/\n/\\n/g' "${POD_TEMP_PATH}/${KUBERNETES_CA_FILENAME}")

$POD_VAULT_CMD auth enable -path ${MOUNT} kubernetes

$POD_VAULT_CMD write auth/${MOUNT}/config \
    token_reviewer_jwt="${TOKEN_REVIEW_JWT}" \
    kubernetes_host="${KUBE_HOST}" \
    kubernetes_ca_cert="${KUBE_CA_CERT}" \
    disable_issuer_verification=true

$POD_VAULT_CMD write auth/${MOUNT}/role/vault-secrets-operator \
    bound_service_account_names=${SERVICE_ACCOUNT_NAME} \
    bound_service_account_namespaces=default \
    policies=${POLICY_NAME} \
    ttl=1h
EOF
chmod +x "${POD_SCRIPT_FILE}"

# Configure the openbao to give access to vso
$KUBECTL_OPENBAO cp "${KUBERNETES_CA_FILE}" "${NS_OPENBAO}/${OPENBAO_POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL_OPENBAO cp "${POD_SCRIPT_FILE}" "${NS_OPENBAO}/${OPENBAO_POD_NAME}":"${POD_TEMP_PATH}"
$KUBECTL_OPENBAO exec "${OPENBAO_POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"

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
  name: ${VAULT_CONNECTION_NAME}
  namespace: ${NS_APP}
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
    serviceAccount: default
  vaultConnectionRef: ${VAULT_CONNECTION_NAME}
EOF

$KUBECTL apply -f "${VAULT_AUTH_FILE}"

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
  type: kv-v2
  mount: ${MOUNT}
  path: ${SECRET_PATH}
  refreshAfter: 10s
  destination:
    create: true
    name: ${SECRET_NAME}
EOF
$KUBECTL apply -f "${STATIC_SECRET_FILE}"
