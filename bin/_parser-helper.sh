# This files provide snippets of code to ease parsing yaml files
# To be sourced within a shell script:
# source _parser-helper.sh

# Retrieve the value from cluster-configuration/values.yaml, given yaml path
# elements
values_yaml="cluster-configuration/values.yaml"
function get_value() {
  local query='.'
  for key in "$@"; do
    query+="[\"${key}\"]"
  done
  local value
  value=$(yq -r "${query}" "${values_yaml}")
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "Error: yq failed for path '$*' in ${values_yaml}" >&2
    exit 1
  fi
  if [[ "${value}" == "null" || -z "${value}" ]]; then
    echo "Error: value not found for path '$*' in ${values_yaml}" >&2
    exit 1
  fi
  echo "${value}"
}
