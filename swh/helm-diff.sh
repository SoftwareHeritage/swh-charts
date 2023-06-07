#!/bin/bash -e

## Compare the helm output difference between the current branch and the production branch
## All the files must be commited to have an effect
##
## Usage:
## From the base directory of the helm chart, launch:
## ./test.sh

CONTEXT_SIZE=10
MAIN_BRANCH=production
BRANCH="$(git symbolic-ref --quiet HEAD | sed 's|refs/heads/||')"

TMPDIR=$(mktemp -d /tmp/swh-chart.XXXXXXXX)
function cleanup {
    rm -rf $TMPDIR
}

trap cleanup EXIT

echo "Comparing changes between branches $MAIN_BRANCH and $BRANCH..."

files=$(ls values/*.yaml)

HELM_CMD="helm template test . --values ../values-swh-application-versions.yaml --values values.yaml --values values/default.yaml --values"

# git stash
git checkout $MAIN_BRANCH
for f in $files; do
    echo "Generate config in $MAIN_BRANCH branch for $f..."
    output="$TMPDIR/$(basename $f).before"
    $HELM_CMD $f > $output
done

# git stash pop
git checkout $BRANCH
for f in $files; do
    echo "Generate config in ${BRANCH} branch for $f..."
    output="$TMPDIR/$(basename $f).after"
    $HELM_CMD $f > $output
done

for f in $files; do
    output="$TMPDIR/$(basename $f)"

    echo
    echo
    echo "------------- diff for $f -------------"
    echo
    set +e
    diff -U${CONTEXT_SIZE} $output.before $output.after
    [[ $? -gt 0 ]] || echo "No differences"
    set -e
done
