#!/bin/bash -e

## Compare the helm output difference between the current branch and the production branch
## All the files must be commited to have an effect
##
## Usage:
## From the base directory of the helm chart, launch:
## ./test.sh

CONTEXT_SIZE=10
MAIN_BRANCH=production
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
  echo "[$APP] Generate config in $MAIN_BRANCH branch for environment ${environment}..."
  output="$TMPDIR/${environment}.before"

  $HELM_CMD $APP/values/$environment/swh.yaml > $output
  $HELM_CMD $APP/values/$environment/swh-cassandra.yaml >> $output

  if [ "$environment" = "staging" ]; then
    $HELM_CMD $APP/values/$environment/swh-cassandra.yaml \
              --values $APP/values/$environment/overrides/swh-cassandra-next-version.yaml >> $output
  fi

  # git stash pop
  git checkout $BRANCH
  echo "[$APP] Generate config in $BRANCH branch for environment ${environment}..."
  output="$TMPDIR/${environment}.after"

  $HELM_CMD $APP/values/$environment/swh.yaml > $output
  $HELM_CMD $APP/values/$environment/swh-cassandra.yaml >> $output

  if [ "$environment" = "staging" ]; then
    $HELM_CMD $APP/values/$environment/swh-cassandra.yaml \
              --values $APP/values/$environment/overrides/swh-cassandra-next-version.yaml >> $output
  fi
done

# Actually diff the result for each environment

for environment in "staging" "production"; do
    output="$TMPDIR/${environment}"

    echo
    echo
    echo "------------- diff for environment $environment -------------"
    echo
    set +e
    diff -U${CONTEXT_SIZE} $output.before $output.after
    [[ $? -gt 0 ]] || echo "No differences"
    set -e
done