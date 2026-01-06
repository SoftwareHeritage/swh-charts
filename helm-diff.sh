#!/usr/bin/env bash

set -e

## Compare the helm output difference between the current branch and the production branch
## All the files must be commited to have an effect
##
## Usage:
## From the base directory of the helm chart, launch:
## ./test.sh

CONTEXT_SIZE=10
MAIN_BRANCH=production
APP=${1-swh}
BRANCH="$(git symbolic-ref --quiet HEAD | sed 's|refs/heads/||')"

DIFF_COMMAND_TO_USE=${2-auto}
LEGACY_DIFF_COMMAND="diff -U${CONTEXT_SIZE}"
DIFF_COMMAND=""

case $DIFF_COMMAND_TO_USE in
    dyff)
        if command -v dyff >/dev/null; then
            if [ -n "$DYFF_OPTS" ]; then
                DYFF_OPTS="-s -c on"
            fi
            DIFF_COMMAND="dyff between ${DYFF_OPTS}"
            USE_DYFF=true
        fi
    ;;
    diff)
        DIFF_COMMAND="${LEGACY_DIFF_COMMAND}"
        USE_DYFF=false
    ;;
    autodetect|auto|*)
        # do nothing, legacy behavior to auto-detect diff command
        ;;
esac

case "${APP}" in
    cluster-components)
        override_suffix=cc
        ;;
    cluster-configuration)
        override_suffix=ccf
        ;;
    swh)
        override_suffix=swh
        ;;
    *)
        override_suffix=""
    ;;
esac

if [ -z "$DIFF_COMMAND" ]; then
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
fi

TMPDIR=$(mktemp -d /tmp/swh-chart.$APP.XXXXXXXX)
function cleanup {
    rm -rf $TMPDIR
}

trap cleanup EXIT

echo "[$APP] Comparing changes between branches $MAIN_BRANCH and $BRANCH..."

files=$(ls $APP/values/*.yaml)

EXTRA_CMD=""
[ -f $APP/values/default.yaml ] && EXTRA_CMD="--values $APP/values/default.yaml"

HELM_CMD="helm template test $APP --values values-swh-application-versions.yaml --values $APP/values.yaml ${EXTRA_CMD} --values"

# git stash
git checkout $MAIN_BRANCH
for f in $files; do
    filename=$(basename $f)
    echo "[$APP] Generate config in $MAIN_BRANCH branch for $f..."
    EXTRA_CLI_VALUES=()
    if [ "${filename}" = "local-cluster.yaml" -a -n "${override_suffix}" ]; then
        EXTRA_CLI_VALUES+=("--values" "./local-cluster-${override_suffix}.override.yaml")
    fi

    output="$TMPDIR/${filename}.before"
    $HELM_CMD $f "${EXTRA_CLI_VALUES[@]}" > $output
done

# git stash pop
git checkout $BRANCH
for f in $files; do
    filename=$(basename $f)
    echo "[$APP] Generate config in $MAIN_BRANCH branch for $f..."
    EXTRA_CLI_VALUES=()
    if [ "${filename}" = "local-cluster.yaml" -a -n "${override_suffix}" ]; then
        EXTRA_CLI_VALUES+=("--values" "local-cluster-${override_suffix}.override.yaml")
    fi
    output="$TMPDIR/${filename}.after"
    $HELM_CMD $f "${EXTRA_CLI_VALUES[@]}" > $output
done

for f in $files; do
    output="$TMPDIR/$(basename $f)"

    echo
    echo
    echo "------------- diff for $f -------------"
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
