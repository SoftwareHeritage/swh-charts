#!/usr/bin/env bash
# -*- eval: (setq-default sh-indentation 2) -*-

# This script configures the targeted local cluster with vault-secrets-operator:
# * create `vso` and `app` namespaces
# * install vso helm chart inside `vso` namespace
# * configure vault auth from the targeted cluster in the openbao cluster

# This script does not create any secrets yet (see create-secret.sh)

set -e

TEMP_DIR=$(mktemp -d)

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

# Ensure the necessary commands are present on machine
check_for_command_or_raise kubectl || exit 1
check_for_command_or_raise helm || exit 1
check_for_command_or_raise kind || exit 1
check_for_command_or_raise uv || exit 1

# Let's activate the venv
( [ ! -d "${VENV_DIR}" ] && uv venv "${VENV_DIR}" --python 3.11 ) || \
  source "${VENV_DIR}/bin/activate"

# Synchronize from the uv.lock
uv sync

trap _cleanup EXIT

function _cleanup {
  # Cleanup temporary work directory
  rm -rf "${TEMP_DIR}"
  # Deactivate the venv
  source deactivate
}

DESCRIPTION="Configure the vault-secret-operator in targeted CLUSTER_NAME"

CLUSTER_NAME=$1
shift

if [ -z "${CLUSTER_NAME}" -o "${CLUSTER_NAME}" = "-h" -o "${CLUSTER_NAME}" = "--help" ]; then
  echo "Error: Targeted cluster name is mandatory."
  script_usage "${DESCRIPTION}"
  exit 1
fi

set_variables_for_cluster ${CLUSTER_NAME}
DEBUG_INSTRUCTIONS=

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      set -x
      export DEBUG_INSTRUCTIONS=1
      shift
      ;;
    -r|--recreate)
      cluster_recreate "${CLUSTER_NAME}"
      shift
      ;;
    -c|--create)
      cluster_create "${CLUSTER_NAME}"
      shift
      ;;
    -d|--delete)
      cluster_delete "${CLUSTER_NAME}"
      exit 0
      ;;
    -h|--help)
      script_usage "${DESCRIPTION}"
      shift
      ;;
    *)
      echo "Unknown option <$1>"
      script_usage "${DESCRIPTION}"
      exit 1
      ;;
  esac
done

create_shared_ca_files

execute_or_skip ${KUBECTL} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL} create namespace "${NS_APP}"

${HELM} repo add jetstack https://charts.jetstack.io
${HELM} repo add metallb https://metallb.github.io/metallb
${HELM} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# ${HELM} repo add hashicorp https://helm.releases.hashicorp.com/
${HELM} repo update jetstack metallb ingress-nginx

install_or_skip cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true --set installCRDs=true
install_or_skip metallb metallb/metallb --namespace metallb
install_or_skip ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx

# Inject shared ca
execute_or_skip ${KUBECTL} delete secret shared-ca --namespace "${NS_VSO}"
${KUBECTL} create secret generic shared-ca --namespace "${NS_VSO}" \
           --from-file=ca.crt=$CA_CERT_FILECRT

# Let's wait for the ingress stack to be installed (required for argocd
# ingress to deploy)
${KUBECTL} wait pods --all --for=condition=Ready --timeout=60s \
   -n metallb

${KUBECTL} wait pods --all --for=condition=Ready --timeout=60s \
   -n ingress-nginx

${KUBECTL} apply -f - <<EOF
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: "local-metallb-pool-ingress"
  namespace: metallb
spec:
  addresses:
    - ${PRODUCTION_INGRESS_IP}/32
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

# Create a cluster issuer shared-ca-issuer and generate a certificate for openbao
${KUBECTL} apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: shared-ca-issuer
spec:
  ca:
    secretName: shared-ca
EOF

${KUBECTL} apply -f - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubeapi
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    cert-manager.io/cluster-issuer: "shared-ca-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - "${PRODUCTION_INGRESS_HOSTNAME}"
    secretName: production-ingress-tls
  rules:
  - host: "${PRODUCTION_INGRESS_HOSTNAME}"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: kubernetes
            port:
              number: 443
EOF

CLUSTER_FQDN="https://kubernetes.default.svc"
if [ "${CLUSTER_NAME}" != "admin" ]; then
  KUBECFG_PRODFILE=$TEMP_DIR/local-cluster-production.yaml
  # Retrieve the kind configuration for that cluster
  kind get kubeconfig --name $CLUSTER_CONTEXT_PRODUCTION > ${KUBECFG_PRODFILE}
  # Then adapt to use the kubernetes ingress api instead of the host related
  # access (which is not possible from the "admin" cluster)
  URL_TO_REPLACE=$(awk '/server: /{print $2}' ${KUBECFG_PRODFILE})
  CLUSTER_FQDN="https://${PRODUCTION_INGRESS_HOSTNAME}"
  sed -i "s#${URL_TO_REPLACE}#${CLUSTER_FQDN}#gi" ${KUBECFG_PRODFILE}

  CLUSTER_REFNAME="kind-local-cluster-production"
  SECRET_REFNAME="${CLUSTER_REFNAME}-secret"

  execute_or_skip $KUBECTL_ADMIN delete secret -n ${NS_ARGOCD} \
    ${SECRET_REFNAME}

  # FIXME: Call argocd cluster add even though it's not fully finishing with
  # success It's specific to the local cluster and won't be used that way in
  # production any ways.  This cli call will create a service account, cluster
  # role and cluster role binding in the argocd-manager namespace with the
  # sufficient privileges (possibly!?)

  argocd cluster add "${CLUSTER_REFNAME}" -y || \
    echo "argocd cluster add failed, but ServiceAccount, ClusterRole and ClusterRoleBinding should exist now."

  TOKEN_ACCESS=$($KUBECTL_PRODUCTION create token argocd-manager -n kube-system)

  ${KUBECTL_ADMIN} apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_REFNAME}
  namespace: ${NS_ARGOCD}
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${CLUSTER_REFNAME}
  server: ${CLUSTER_FQDN}
  config: |
    {
      "bearerToken": "${TOKEN_ACCESS}",
      "tlsClientConfig": {
        "insecure": true
      }
    }
EOF

fi

VSO_VERSION=1.1.0
# Now that argocd is configured properly to deal with the other cluster, let's
# install vso with argocd!
$KUBECTL_ADMIN apply -f - <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: local-cluster-vso
  namespace: ${NS_ARGOCD}
spec:
  project: default
  source:
    repoURL: https://helm.releases.hashicorp.com/
    chart: vault-secrets-operator
    targetRevision: v${VSO_VERSION}
    helm:
      releaseName: vso
      values: |
        controller:
          manager:
            logging:
              level: trace
          hostAliases:
            - ip: ${ADMIN_INGRESS_IP}
              hostnames:
              - ${ADMIN_INGRESS_HOSTNAME}
            - ip: ${PRODUCTION_INGRESS_IP}
              hostnames:
              - ${PRODUCTION_INGRESS_HOSTNAME}
        defaultVaultConnection:
          enabled: true
          address: ${OPENBAO_ENDPOINT}
          caCertSecret: shared-ca
  destination:
    server: ${CLUSTER_FQDN}
    namespace: ${NS_VSO}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF


# Wait for argocd sync window to kick in
${KUBECTL} wait deployment -n "${NS_VSO}" --all --for=condition=Available \
  --timeout=60s || \
  ( echo "Waiting with argocd ns failed... " && \
    echo "Let's fallback to sleep to give some time for argocd sync window to kick in." \
    && sleep 5 )

${KUBECTL} wait deployment -n "${NS_VSO}" --all --for=condition=Available \
  --timeout=60s

echo "Start configuring BAO resources in cluster <${CLUSTER_REFNAME}>..."

# See documentation and examples here:
# https://developer.hashicorp.com/vault/api-docs/system/mounts
# https://support.hashicorp.com/hc/en-us/articles/4412233931667-Translate-Vault-CLI-commands-to-HTTP-API
# https://gist.github.com/exAspArk/e210523a4bcb988cdfb24a114d46ddf0

${KUBECTL_ADMIN} wait pod --all --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

# Create secret engine
./init_bao_cluster.py --url ${OPENBAO_ENDPOINT} \
                      --token ${OPENBAO_DEFAULT_TOKEN} \
                      enable-secrets-engine ${MOUNT} 2>/dev/null

# Then we create the policy for the future approle to create
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

./init_bao_cluster.py --url ${OPENBAO_ENDPOINT} \
                      --token ${OPENBAO_DEFAULT_TOKEN} \
                      create-policy ${POLICY_NAME} ${POLICY_FILE} 2>/dev/null

# Finally we attach that policy to the new AppRole we create
./init_bao_cluster.py --url ${OPENBAO_ENDPOINT} \
                      --token ${OPENBAO_DEFAULT_TOKEN} \
                      create-approle \
                        --mount ${MOUNT} \
                        --policy-name ${POLICY_NAME} \
                        ${ROLE} 2>/dev/null

ROLE_ID=$(./init_bao_cluster.py --url ${OPENBAO_ENDPOINT} \
                                --token ${OPENBAO_DEFAULT_TOKEN} \
                                get-approle-id ${ROLE} \
                                --mount ${MOUNT} \
                                2>/dev/null)

SECRET_ID=$(./init_bao_cluster.py --url ${OPENBAO_ENDPOINT} \
                                  --token ${OPENBAO_DEFAULT_TOKEN} \
                                  create-approle-secret-id ${ROLE} \
                                  --mount ${MOUNT} \
                                  2>/dev/null)

ROLE_SECRET_NAME="${ROLE}-secret"

execute_or_skip ${KUBECTL} delete secret "${ROLE_SECRET_NAME}" --namespace "${NS_APP}"
${KUBECTL} create secret generic "${ROLE_SECRET_NAME}" --namespace "${NS_APP}" \
               --from-literal=id="${SECRET_ID}"

${KUBECTL} apply -f - << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${VAULT_AUTH_NAME}
  namespace: ${NS_APP}
spec:
  method: appRole
  mount: ${MOUNT}
  appRole:
    roleId: ${ROLE_ID}
    secretRef: ${ROLE_SECRET_NAME}
  allowedNamespaces:
    - "*"
EOF
