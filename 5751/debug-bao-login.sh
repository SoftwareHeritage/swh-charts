#!/usr/bin/env bash

set -ex

# -------------------------------------------------
# 1. Variables – adjust only if you renamed them
# -------------------------------------------------
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

# -------------------------------------------------
# 2. Get the ServiceAccount JWT that the pod would use
# -------------------------------------------------
# # The token is stored in a secret named <sa>-token-<random>
# SA_SECRET=$($KUBECTL_VSO -n "${NS_APP}" get secret \
#   -l kubernetes.io/service-account.name="${SERVICE_ACCOUNT_NAME}" \
#   -o jsonpath='{.items[0].metadata.name}')

# if [[ -z "${SA_SECRET}" ]]; then
#   echo "Could not find a secret for ServiceAccount ${SERVICE_ACCOUNT_NAME} in ${NS_APP}"
#   exit 1
# fi
SA_SECRET=default-secret
SA_JWT=$($KUBECTL_VSO -n "${NS_APP}" get secret "${SA_SECRET}" -o jsonpath='{.data.token}' | base64 --decode)
# SA_JWT=$($KUBECTL_OPENBAO -n "${NS_APP}" get secret "${SA_SECRET}" -o jsonpath='{.data.token}' | base64 --decode)

# echo $SA_JWT
# echo $ROLE

# -------------------------------------------------
# 3. Build the JSON payload
# -------------------------------------------------
PAYLOAD_FILE="${TEMP_DIR}/login-payload.json"
cat <<EOF > "${PAYLOAD_FILE}"
{
  "jwt": "${SA_JWT}",
  "role": "${ROLE}"
}
EOF

# -------------------------------------------------
# 4. Perform the request (http or https)
# -------------------------------------------------
URL="https://${OPENBAO_INGRESS_HOSTNAME}/v1/auth/${MOUNT}/login"

echo "Sending request to ${URL}"
echo "Payload:"
cat "${PAYLOAD_FILE}" | jq .

# Use curl - show request/response details
curl -i -X POST "${URL}" \
  -H "Content-Type: application/json" \
  --cacert "${CA_CERT_FILECRT}" \
  -d @"${PAYLOAD_FILE}"
