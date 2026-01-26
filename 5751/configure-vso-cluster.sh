#!/usr/bin/env bash

# This script configures the environment cluster for VSO deployment:
# * create `vso` and `app` namespaces
# * install vso helm chart inside `vso` namespace
# * configure vault auth from vso cluster

set -xe

TEMP_DIR=$(mktemp -d)
#trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

# To configure properly the install_or_skip function
HELM=$HELM_VSO

if [[ "$1" == "--delete" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_VSO}"
  exit 0
elif [[ "$1" == "--reset" ]]; then
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT_VSO}"
  "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT_VSO}" kind "true" 8080 8443
elif [[ "$1" == "--cleanup" ]]; then
  # If --cleanup is set, remove existing resources
  ${HELM_VSO} uninstall vault-secrets-operator || true
#  ${KUBECTL_VSO} delete namespace "${NS_VSO}" || true
fi

if [ ! -d $CA_CERT_DIR ]; then
    mkdir -p $CA_CERT_DIR
    # Generate private rsa key
    openssl genrsa -out $CA_CERT_FILEKEY 4096

    # Ensure no issues occurred
    [ ! -f $CA_CERT_FILEKEY ] && echo "<$CA_CERT_FILEKEY> must exist!" && exit 1

    # Self-signed shared root certificate in between kind clusters
    openssl req -x509 -new -nodes -key $CA_CERT_FILEKEY \
            -sha256 -days 3650 \
            -subj "/CN=shared-local-clusters-ca" \
            -out $CA_CERT_FILECRT
    # Ensure no issues occurred
    [ ! -f $CA_CERT_FILECRT ] && echo "<$CA_CERT_FILECRT> must exist!" && exit 1
fi

execute_or_skip ${KUBECTL_VSO} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL_VSO} create namespace "${NS_APP}"

${HELM_VSO} repo add jetstack https://charts.jetstack.io
${HELM_VSO} repo add metallb https://metallb.github.io/metallb
${HELM_VSO} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
${HELM_VSO} repo update jetstack metallb ingress-nginx

install_or_skip cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true \
  --set installCRDs=true \
  --set "hostAliases[0].ip=${VSO_INGRESS_IP}" \
  --set "hostAliases[0].hostnames[0]=${VSO_INGRESS_HOSTNAME}"
install_or_skip metallb metallb/metallb --namespace metallb

# Inject shared ca
execute_or_skip ${KUBECTL_VSO} create secret tls shared-ca --namespace cert-manager \
  --cert=$CA_CERT_FILECRT --key=$CA_CERT_FILEKEY
execute_or_skip ${KUBECTL_VSO} create secret tls shared-ca --namespace "${NS_VSO}" \
  --cert=$CA_CERT_FILECRT --key=$CA_CERT_FILEKEY
execute_or_skip ${KUBECTL_VSO} create configmap shared-ca  \
  --namespace "${NS_VSO}" --from-file=ca.crt=$CA_CERT_FILECRT

${KUBECTL_VSO} apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: shared-ca-issuer
spec:
  ca:
    secretName: shared-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vso-tls-cert
spec:
  secretName: vso-tls-secret   # will contain tls.crt & tls.key
  commonName: ${VSO_INGRESS_HOSTNAME}
  dnsNames:
  - ${VSO_INGRESS_HOSTNAME}   # FQDN that the vso pod will use
  issuerRef:
    name: shared-ca-issuer
    kind: ClusterIssuer
EOF

${KUBECTL_VSO} wait certificate vso-tls-cert --for=condition=Ready --timeout=60s

# TODO copy vso-tls-secret secret into vso & default namespaces, temporary workaround obviously
execute_or_skip ${KUBECTL_VSO} delete secret vso-tls-secret -n "${NS_VSO}"
${KUBECTL_VSO} get secret vso-tls-secret -o yaml | sed 's/namespace: default/namespace: vso/' | ${KUBECTL_VSO} apply -f -

install_or_skip ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set "controller.defaultTLS.secret=default/vso-tls-secret"

# Enable ingress controller load balancer IP allocation through metallb
${KUBECTL_VSO} wait pod --all --for=condition=Ready --timeout=60s -n metallb

${KUBECTL_VSO} apply -f - <<EOF
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: "local-metallb-pool-ingress"
  namespace: metallb
spec:
  addresses:
    - ${VSO_INGRESS_IP}/32
  serviceAllocation:
    namespaces:
    - ingress-nginx
    priority: 50
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: "l2-advertisement-ingress"
  namespace: metallb
spec:
  ipAddressPools:
  - "local-metallb-pool-ingress"
EOF

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

execute_or_skip ${KUBECTL_VSO} create namespace "${NS_APP}"

${KUBECTL_VSO} apply -f "${VAULT_AUTH_FILE}"
execute_or_skip ${KUBECTL_VSO} create clusterrolebinding "${CLUSTER_ROLE_BINDING_NAME}" \
    --clusterrole=system:auth-delegator \
    --serviceaccount="${NS_APP}:${SERVICE_ACCOUNT_NAME}"

POLICY_FILENAME="${POLICY_NAME}.hcl"
POLICY_FILE="${TEMP_DIR}/${POLICY_FILENAME}"
cat > "${POLICY_FILE}" << EOF

path "auth/${MOUNT}/login" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "${MOUNT}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "${MOUNT}/login" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

# Define a service account token secret that is used by openbao to authenticate to
# Kubernetes.
execute_or_skip ${KUBECTL_VSO} delete secret "${SERVICE_ACCOUNT_NAME_SECRET}" -n "${NS_APP}"

# Note: the secret type service-account-token is definitely not working. The jwt token
# generated hardcodes an irrelevant issuer from the kubernetes `kubeapi`
# (`kubernetes/serviceaccount` while it should use the `
# --service-account-issuer=https://kubernetes.default.svc.cluster.local` which is the
# value configured for the kubeapi
${KUBECTL_VSO} apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SERVICE_ACCOUNT_NAME_SECRET}
  namespace: ${NS_APP}
  annotations:
    kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
type: kubernetes.io/service-account-token
EOF

${KUBECTL_VSO} wait pod --all --for=condition=Ready --timeout=60s -n ingress-nginx

${KUBECTL_VSO} apply -f - <<EOF
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
#${KUBECTL_VSO} get secret vso-tls-secret -o jsonpath="{.data['ca\.crt']}" | base64 --decode > "${VSO_TLS_CA_CRT_FILE}"
#
#VSO_TLS_CRT_FILE="${TEMP_DIR}/vso-tls.crt"
#${KUBECTL_VSO} get secret vso-tls-secret -o jsonpath="{.data['tls\.crt']}" | base64 --decode > "${VSO_TLS_CRT_FILE}"
#
#VSO_TLS_KEY_FILE="${TEMP_DIR}/vso-tls.key"
#${KUBECTL_VSO} get secret vso-tls-secret -o jsonpath="{.data['tls\.key']}" | base64 --decode > "${VSO_TLS_KEY_FILE}"
#
#${KUBECTL_VSO} create token "${SERVICE_ACCOUNT_NAME}" --namespace "${NS_APP}" \
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

SA_PUB_FILENAME="sa.pub"
SA_PUB_FILE="${TEMP_DIR}/${SA_PUB_FILENAME}"
CONTROL_PLANE_NODE="local-cluster-${CLUSTER_NAME_VSO}-control-plane"
# (workaround) Retrieve sa.pub from the control plane node
docker cp "${CONTROL_PLANE_NODE}:/etc/kubernetes/pki/${SA_PUB_FILENAME}" "${SA_PUB_FILE}"
# Copy locally to help
docker cp "${CONTROL_PLANE_NODE}:/etc/kubernetes/pki/${SA_PUB_FILENAME}" "${SA_PUB_FILENAME}"

CA_CRT_FILENAME="ca.crt"
CA_CRT_FILE="${TEMP_DIR}/${CA_CRT_FILENAME}"

${KUBECTL_VSO} get secret vso-tls-secret -o jsonpath="{.data['tls\.crt']}" | base64 --decode | tee "${TLS_CRT_FILE}"
echo "TLS_CRT_FILE: $(cat ${TLS_CRT_FILE})"

${KUBECTL_VSO} get secret "${SERVICE_ACCOUNT_NAME_SECRET}" -n "${NS_APP}" -o jsonpath="{.data['ca\.crt']}" | base64 --decode | tee "${CA_CRT_FILE}"
echo "CA_CRT_FILE: $(cat ${CA_CRT_FILE})"

SA_TOKEN=$(${KUBECTL_VSO} get secret "${SERVICE_ACCOUNT_NAME_SECRET}" -n "${NS_APP}" -o jsonpath="{.data.token}")
echo "SA_TOKEN: ${SA_TOKEN}"

SA_TOKEN_DECODED=$(echo "${SA_TOKEN}" | base64 --decode)
echo "SA_TOKEN_DECODED: ${SA_TOKEN_DECODED}"

# TOKEN_TTL=1h
# AUDIENCE="https://kubernetes.default.svc.cluster.local"

# TOKEN_GENERATED_FILE=${TEMP_DIR}/token-request.yaml

# # TODO: Require a token from openbao instead?

# $KUBECTL_VSO create token "${SERVICE_ACCOUNT_NAME}" --namespace "${NS_APP}" \
#   --audience $AUDIENCE \
#   --duration $TOKEN_TTL \
#   -o jsonpath='{.status.token}' > "${TOKEN_GENERATED_FILE}"

# SA_TOKEN_DECODED=$(cat "${TOKEN_GENERATED_FILE}")
# echo "SA_TOKEN_DECODED: ${SA_TOKEN_DECODED}"

# set -x

# $KUBECTL_VSO create secret generic "${SERVICE_ACCOUNT_NAME_SECRET}" \
#   --namespace "${NS_APP}" \
#   --from-file=sa.pub="${SA_PUB_FILE}" \
#   --from-literal=token="${SA_TOKEN_DECODED}"

# # Create secret with the token generated so we can use it in other parts
# $KUBECTL_VSO apply -f - <<EOF
# ---
# apiVersion: v1
# kind: Secret
# metadata:
#   name: ${SERVICE_ACCOUNT_NAME_SECRET}
#   namespace: ${NS_APP}
# type: kubernetes.io/tls
# stringData:
#   sa.pub: $(cat $SA_PUB_FILE | base64 -w0)
#   token: ${SA_TOKEN_DECODED}
# EOF

# Make it readable a bit
JWT_JSON=$(echo "$SA_TOKEN_DECODED" | cut -d. -f2 | base64 -d 2>/dev/null | jq .)
echo "jwt payload: $(echo $JWT_JSON | jq .)"

# Retrieve the jwt token issuer
#ISSUER=$($KUBECTL_VSO get --raw /.well-known/openid-configuration | jq -r .issuer)
ISSUER="kubernetes/serviceacccount"
# ISSUER=$(echo $JWT_JSON | jq .iss | tr -d '"')
echo "Token Issuer: ${ISSUER}"

# validation test -> does not work somehow
# curl -H "Authorization: Bearer ${SA_TOKEN_DECODED}" \
#      --cacert "${CA_CERT_FILECRT}" \
#      https://${VSO_INGRESS_HOSTNAME}/api/v1/pods

# TODO: How to attach this generated token to the service account?

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
# ${POD_VAULT_CMD} write "auth/${MOUNT}/config" \
#   kubernetes_host="https://${VSO_INGRESS_HOSTNAME}:${VSO_INGRESS_PORT}" \
#   disable_local_ca_jwt=true \
#   token_reviewer_jwt="${SA_TOKEN_DECODED}" \
#   pem_keys=@"${POD_TEMP_PATH}/${SA_PUB_FILENAME}" \
#   kubernetes_ca_cert=@"${POD_TEMP_PATH}/${TLS_CRT_FILENAME}" \
#   issuer="${ISSUER}" \
#   disable_iss_validation=false

# Deactivate "iss"uer validation when using service-account-token secret as there is an
# inconsistent behavior in kind(kubernetes?) regarding the issuer set in the generated
# service-account-token jwt. The kubeapi is set to use
# 'https://kubernetes.default.svc.cluster.local' but the jwt
# token when decoded has an iss set to kubernetes/serviceaccount which makes the
# openbao/vault-secret-operators refuse to communicate properly... (between the hammer
# and the anvil kind of situation)

${POD_VAULT_CMD} write "auth/${MOUNT}/config" \
  kubernetes_host="https://${VSO_INGRESS_HOSTNAME}:${VSO_INGRESS_PORT}" \
  kubernetes_ca_cert=@"${POD_TEMP_PATH}/${TLS_CRT_FILENAME}" \
  token_reviewer_jwt="${SA_TOKEN_DECODED}" \
  pem_keys=@"${POD_TEMP_PATH}/${SA_PUB_FILENAME}" \
  disable_local_ca_jwt=true \
  disable_iss_validation=true

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
  policies="${POLICY_NAME}" \
  audience="${AUDIENCE}"

echo "### Created Vault Kubernetes auth role:"
${POD_VAULT_CMD} read "auth/${MOUNT}/role/${ROLE}"
echo "#######################################"
EOF
chmod +x "${POD_SCRIPT_FILE}"

${KUBECTL_OPENBAO} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

POD_NAME=$($KUBECTL_OPENBAO get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")
POD_DEST_PATH="${NS_OPENBAO}/${POD_NAME}":"${POD_TEMP_PATH}"

$KUBECTL_OPENBAO cp "${POLICY_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO cp "${TLS_CRT_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO cp "${CA_CRT_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO cp "${SA_PUB_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO cp "${POD_SCRIPT_FILE}" "${POD_DEST_PATH}"
$KUBECTL_OPENBAO exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "${POD_TEMP_PATH}/${POD_SCRIPT_FILENAME}"
