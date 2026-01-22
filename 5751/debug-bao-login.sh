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
#SA_SECRET=default-secret
#SA_JWT=$($KUBECTL_VSO -n "${NS_APP}" get secret "${SA_SECRET}" -o jsonpath='{.data.token}' | base64 --decode)
SA_JWT="eyJhbGciOiJSUzI1NiIsImtpZCI6Im1UeG1BVnZ6RnNuaUJWTjF5MTE0N3NaNmNxdlBPREFFZ3FSWnZocU0xUkEifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJhcHAiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlY3JldC5uYW1lIjoiZGVmYXVsdC1zZWNyZXQiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGVmYXVsdCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6ImMzYmRjZjNmLTRjNWUtNDQyZi05ZWMzLWI0ZDQ1MDg2YWU1NSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDphcHA6ZGVmYXVsdCJ9.DQ1L4_n0A1S2kSvxoqjTrkwbNk8TkNemPdTkbZSUwUYhHCcK-fIN2b9L3Qpr066JpbNETccyiFCPAT5Pyvhio6qbu1dfNCig2X7zYHkiDzrK9GWdEDfropAXdCQZ7fmHNQknONYcieRseTRPJtHT8r1Bsh2CUOVh6KCX40HXfCPHcLxViqAZgT7vCIdqc3lWfjuhQjqDKk4FFf1Dy5wbUZ8smC1KbMdi5uCQrx6m1buTZo_ML6frytM7orCeua8xXjHXRitiBfLRnhJ0X6ZMvMX4klbowmv2Gmk5QTxDPFRzinQoW3pgQ8WZmezIJIkzneMkm-QZ-7FeNKDlAj0zOQ"
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

# Use curl – show request/response details
curl -i -s -X PUT "${URL}" \
  -H "Content-Type: application/json" \
  --cacert "${CA_CERT_FILECRT}" \
  -d @"${PAYLOAD_FILE}"
