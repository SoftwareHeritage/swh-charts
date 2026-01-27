function install_or_skip {
  helm_name=$1; shift
  helm_repo=$1; shift

  if [ -z "$DEBUG_INSTRUCTIONS" ]; then
    ${HELM} install \
      $helm_name $helm_repo \
      --create-namespace "$@" > /dev/null 2>&1 || \
      echo "<$helm_name> already installed!"
  else
    ${HELM} install \
      $helm_name $helm_repo \
      --create-namespace "$@" || \
      echo "<$helm_name> already installed!"
  fi
}

function uninstall_or_skip {
  helm_name=$1; shift

  if [ -z "$DEBUG_INSTRUCTIONS" ]; then
    ${HELM} \
      uninstall $helm_name "$@" > /dev/null 2>&1 || \
      echo "<$helm_name> already installed!"
  else
    ${HELM} \
      uninstall $helm_name "$@" || \
      echo "<$helm_name> already installed!"
  fi
}


function execute_or_skip {
  if [ -z "$DEBUG_INSTRUCTIONS" ]; then
    "$@" > /dev/null 2>&1 || echo "<$@> already done, skipping!"
  else
    "$@" || echo "<$@> already done, skipping!"
  fi
}

# Recreate cluster from scratch
cluster_recreate() {
  local cluster_name="$1"
  cluster_delete "${cluster_name}"
  cluster_create "${cluster_name}"
}

# Delete existing cluster
cluster_delete() {
  local cluster_name="$1"
  echo "Delete cluster <$cluster_name>..."
  "${BIN_DIR}/local-cluster-delete.sh" "${CLUSTER_CONTEXT}"
}

# Create inexistant cluster
cluster_create() {
  local cluster_name="$1"
  echo "Create cluster <$cluster_name>..."
  case "${cluster_name}" in
    admin|openbao)
      "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT}" kind "true" 80 443
    ;;
    *)
      "${BIN_DIR}/local-cluster-create.sh" "${CLUSTER_CONTEXT}" kind "false"
    ;;
  esac
}

# Display helm message
script_usage() {
  description="$1"
  echo "Usage: $0 CLUSTER_NAME [OPTIONS]"
  echo -e "\n${description}\n"
  echo "Options:"
  echo "  -c, --create   Create targeted cluster"
  echo "  -r, --recreate Reset targeted cluster"
  echo "  -d, --delete   Delete targeted cluster"
  echo "  --debug        Enable verbose instructions"
  echo "  -h, --help     Display this help message"
  exit 1
}

# Prepare default variables depending on the targeted cluster
function set_variables_for_cluster {
  CLUSTER_NAME=$1

  case "${CLUSTER_NAME}" in
    vso)
      HELM=$HELM_VSO
      KUBECTL=$KUBECTL_VSO
      CLUSTER_CONTEXT=$CLUSTER_CONTEXT_VSO
      ;;
    openbao)
      HELM=$HELM_OPENBAO
      KUBECTL=$KUBECTL_OPENBAO
      CLUSTER_CONTEXT=$CLUSTER_CONTEXT_OPENBAO
      ;;
    *)
      echo "Unknown cluster <${CLUSTER_NAME}>";
      exit 1
      ;;
  esac
  ROLE="role-${CLUSTER_NAME}"
  MOUNT="mount-${CLUSTER_NAME}"
  POLICY_NAME="policy-${CLUSTER_NAME}"
  VAULT_AUTH_NAME="auth-${CLUSTER_NAME}"
}

# Create the shared ca in $CA_CERT_DIR (this is volatile in /tmp but reusable across
# reset)
# This must be persistent because it's used across at least 2 different clusters
function create_shared_ca_files {
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
}
