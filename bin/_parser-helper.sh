# This files provide snippets of code to ease parsing yaml files
# To be sourced within a shell script:
# source _parser-helper.sh

# Retrieves the value from the following files (in order, latest has precedence):
# - cluster-configuration/values.yaml
# - cluster-configuration/values/local-cluster.yaml
# - local-cluster-ccf.override.yaml
values_yaml=("cluster-configuration/values.yaml" "cluster-configuration/values/local-cluster.yaml")

# This optional file might not exist so check for its existence first
optional_values_yaml="local-cluster-ccf.override.yaml"
if [ -f "${optional_values_yaml}" ]; then
  values_yaml+=($optional_values_yaml)
fi

function get_value() {
  local query='.'
  for key in "$@"; do
    query+="[\"${key}\"]"
  done
  local value
  config_files="${values_yaml[@]}"
  # Retrieve config values in inversed order (so priority is from 1st to last)
  values=$(yq -r "${query}" ${config_files} | tac)
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "Error: yq failed for path '$*' in ${values_yaml}" >&2
    return 1
  fi
  for value in $values; do
    if [ "${value}" != "null" ]; then
      echo "${value}"
      return 0
    fi
  done
  # If we reach this part, we did not find any value so we fail the call
  echo "Error: value not found for path '$*' in ${values_yaml}" >&2
  return 1
}
