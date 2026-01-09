# This files provide snippets of code to ease parsing yaml files
# To be sourced within a shell script:
# source _parser-helper.sh

function _init_setup_and_checks {
  # This ensures we configure correctly the required variables but also that we have the
  # necessary tools installed in the system

  [ -z "${CLUSTER_CONTEXT}" ] && \
    echo "<CLUSTER_CONTEXT> env variable must be configured" && \
    exit 1

  if ! command -v yq 2>&1 >/dev/null; then
    echo "Error: yq is not installed." >&2
    exit 1
  fi

  export HELM="helm --kube-context ${CLUSTER_CONTEXT}"
  export KUBECTL="kubectl --context ${CLUSTER_CONTEXT}"
}

# Retrieves the value from the following files (in order, latest has precedence):
# - cluster-configuration/values.yaml
# - cluster-configuration/values/local-cluster.yaml
# - local-cluster-ccf.override.yaml
config_files=(
  "cluster-configuration/values.yaml"
  "cluster-configuration/values/local-cluster.yaml"
)

# This optional file might not exist so check for its existence first
optional_config_file="local-cluster-ccf.override.yaml"
if [ -f "${optional_config_file}" ]; then
  config_files+=("${optional_config_file}")
fi

function prepend() {
  local -n _array=$1
  local _value=$2
  arr=("${_value}" "${_array[@]}")
  echo $arr
}

function get_value() {
  local query='.'
  for key in "$@"; do
    query+="[\"${key}\"]"
  done
  local values=()
  # Retrieve config values in inversed order (so priority is from 1st to last)
  for config_file in ${config_files[@]}; do
    [ ! -f "${config_file}" ] && echo "skipped ${config_file}" && continue
    # The file exists, we parse the value
    value=$(yq -r "${query}" ${config_file})
    if [[ $? -ne 0 ]]; then
      echo "Error: yq failed for path '$*' in <${config_file}>" >&2
      return 1
    fi

    # We keep the value and prepend it in the values array
    # so the last value as higher priority
    values+=("${value}")
  done

  # Iterate over the values in reverse order
  for (( i=${#values[@]}-1; i>=0; i-- )); do
    value="${values[$i]}"
    if [ "${value}" != "null" ]; then
      echo "${value}"
      return 0
    fi
  done

  # If we reach this part, we did not find any value so we fail the call
  echo "Error: value not found for path '$*' in ${values_yaml}" >&2
  return 1
}

# Now actually installs the various operator dependencies

function _helm_uninstall {
  helm_chart_name=$1
  ns=$2
  $HELM uninstall $helm_chart_name --namespace $ns 2>/dev/null || \
      echo "Non critical helm uninstall issue, skipping..."
}

function _kubectl_delete {
  url_or_file=$1
  extra_args=()
  if [ -n "${2}" ]; then
    extra_args+=("--namespace" "${2}")
  fi
  $KUBECTL delete "${extra_args[@]}" -f ${url_or_file} 2>/dev/null || \
      echo "Non critical deletion issue, skipping..."
}
