#!/usr/bin/env bash

TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
fi

TOKEN_PATH=${1-""}

if [ -n "${TOKEN_PATH}" ]; then
  [ -f $TOKEN_PATH ] && SA_TOKEN_JWT=$(cat $TOKEN_PATH) || (\
    echo "<${TOKEN_PATH}> does not exist!" && \
    exit 1)
else
  SA_TOKEN_JWT=$(${KUBECTL_VSO} get secret "${SERVICE_ACCOUNT_NAME_SECRET}" \
    -n "${NS_APP}" -o jsonpath="{.data.token}" | base64 -d)
  echo "SA_TOKEN: ${SA_TOKEN_JWT}"
  echo
  echo "<SA_TOKEN_JWT> dotted count separation (should be 3): "
  echo $SA_TOKEN_JWT | awk -F. '{print NF}'
fi

if [[ "$(awk -F. '{print NF}' <<<"$SA_TOKEN_JWT")" -ne 3 ]]; then
  echo "Not a JWT (expected 3 parts, got $(awk -F. '{print NF}' <<<"$SA_TOKEN_JWT"))"
  exit 1
fi

# Helper to base64-url-decode (the JWT uses URL-safe alphabet)
b64url_decode() {
  local data=$1
  # Pad with = to a multiple of 4
  local pad=$(( (4 - ${#data} % 4) % 4 ))
  data=$(printf "%s%s" "$data" "$(printf '=%.0s' $(seq 1 $pad))")
  echo "$data" | tr '_-' '/+' | base64 -d
}
# Split the token
IFS='.' read -r headers payload signature <<<"$SA_TOKEN_JWT"

echo "-- Base64 encoded jwt --"
echo "----- HEADER -----"
echo $headers
echo "----- PAYLOAD -----"
echo $payload
echo "----- SIG -----"
echo $signature

echo "-- Base64 decoded jwt --"
echo "----- HEADER -----"
b64url_decode "$headers" | jq .
echo "----- PAYLOAD -----"
b64url_decode "$payload" | jq .
echo "----- SIGNATURE (binary, hex) -----"
b64url_decode "$signature" | hexdump -C

#set -x

VSO_SA_PUBKEY_FILE="${TEMP_DIR}/sa.pub"

$KUBECTL_VSO get secret "${SERVICE_ACCOUNT_NAME_SECRET}" --namespace "${NS_APP}" \
  -o jsonpath="{.data['sa\.pub']}" | base64 --decode > "${VSO_SA_PUBKEY_FILE}"

echo "######"
echo "api pubkey file: ${VSO_SA_PUBKEY_FILE}"
cat "${VSO_SA_PUBKEY_FILE}"
echo "######"

# The data that was signed is "header.payload" (still base64‑url, not decoded)
signed_data="${headers}.${payload}"

# Verify with OpenSSL (RS256 = SHA‑256 with RSA PKCS#1 v1.5)
printf "%s" "$signed_data" | \
  openssl dgst -sha256 -verify "${VSO_SA_PUBKEY_FILE}" \
  -signature <(b64url_decode "${signature}") > /dev/null && \
  echo "Signature verification: OK" || \
  echo "Signature verification: FAILED"

# -------------------------------------------------------------------------
# OPTIONAL: ask the API server to “review” the token (same check OpenBao does)
# -------------------------------------------------------------------------
# TOKEN_FILE_PAYLOAD="${TEMP_DIR}/tokenreview.json"
# cat > "${TOKEN_FILE_PAYLOAD}" <<EOF
# {
#   "apiVersion": "authentication.k8s.io/v1",
#   "kind": "TokenReview",
#   "spec": {
#     "token": "${SA_TOKEN_JWT}"
#   }
# }
# EOF

# # Use the same host/CA that you will give to OpenBao
# curl -s --cacert "${VSO_SA_PUBKEY_FILE}" \
#   -H "Content-Type: application/json" \
#   -X POST "https://${VSO_INGRESS_HOSTNAME}/apis/authentication.k8s.io/v1/tokenreviews" \
#   -d @"${TOKEN_FILE_PAYLOAD}" | jq .
