#!/usr/bin/env bash 

set -e

## Compare the helm output difference between the current branch and the production branch
## All the files must be commited to have an effect
##
## Usage:
## From the base directory of the helm chart, launch:
## ./test.sh

CONTEXT_SIZE=10
MAIN_BRANCH=${1:-production}
APP=swh
BRANCH="$(git symbolic-ref --quiet HEAD | sed 's|refs/heads/||')"

TMPDIR=$(mktemp -d /tmp/swh-chart.$APP.XXXXXXXX)
function cleanup {
    rm -rf $TMPDIR
}

trap cleanup EXIT

echo "[$APP] Comparing changes between branches $MAIN_BRANCH and $BRANCH (per environment)..."

# Compute the different templates for each environment

for environment in "staging" "production"; do
  HELM_CMD="helm template test $APP --values values-swh-application-versions.yaml --values $APP/values.yaml --values $APP/values/default.yaml --values $APP/values/$environment/default.yaml --values"

  git checkout $MAIN_BRANCH

  for namespace in "swh" "swh-cassandra" "swh-cassandra-next-version"; do
    echo "[$APP] Generate config in $MAIN_BRANCH branch for environment ${environment}, namespace ${namespace}..."
    output="$TMPDIR/${environment}-${namespace}.before"

    if [ -f $APP/values/$environment/$namespace.yaml ]; then
      $HELM_CMD $APP/values/$environment/$namespace.yaml > $output
    elif [ -f $APP/values/$environment/overrides/$namespace.yaml ]; then
      # Deal with cassandra-next-version
      $HELM_CMD $APP/values/$environment/swh-cassandra.yaml \
        --values $APP/values/$environment/overrides/$namespace.yaml > $output
    fi
  done


  # git stash pop
  git checkout $BRANCH
  for namespace in "swh" "swh-cassandra" "swh-cassandra-next-version"; do
    echo "[$APP] Generate config in $BRANCH branch for environment ${environment}..."
    output="$TMPDIR/${environment}-${namespace}.after"

    if [ -f $APP/values/$environment/$namespace.yaml ]; then
      $HELM_CMD $APP/values/$environment/$namespace.yaml > $output
    elif [ -f $APP/values/$environment/overrides/$namespace.yaml ]; then
      # Deal with cassandra-next-version
      $HELM_CMD $APP/values/$environment/swh-cassandra.yaml \
        --values $APP/values/$environment/overrides/$namespace.yaml > $output
    fi
  done
done

# Actually diff the result for each environment

LEGACY_DIFF_COMMAND="diff -U${CONTEXT_SIZE}"

if command -v dyff >/dev/null; then
  if [ -n "$DYFF_OPTS" ]; then
    DYFF_OPTS="-s -c on"
  fi
  DIFF_COMMAND="dyff between ${DYFF_OPTS}"
  USE_DYFF=true
else
  DIFF_COMMAND="${LEGACY_DIFF_COMMAND}"
  USE_DYFF=false
fi

for environment in "staging" "production"; do
  for namespace in "swh" "swh-cassandra" "swh-cassandra-next-version"; do
    output="$TMPDIR/${environment}-${namespace}"

    if [ ! -f "${output}.before" ]; then
        continue
    fi

    echo
    echo
    echo "------------- diff for environment ${environment} namespace ${namespace} -------------"
    echo
    diff_retval=0

    $DIFF_COMMAND "$output.before" "$output.after" || diff_retval=$?

    if [ "$USE_DYFF" = "true" ]; then
      if [ "$diff_retval" -eq 255 ]; then
        echo "dyff failed, falling back to the legacy diff command"
        $LEGACY_DIFF_COMMAND "$output.before" "$output.after" || echo "No differences"
      fi
    else
      if [ "$diff_retval" -eq 0 ]; then
        echo "No differences"
      fi
    fi
  done
done
