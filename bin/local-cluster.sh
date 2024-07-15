#!/usr/bin/env bash

# This script is an orchestrator to do some action in the local cluster

function usage() {
    echo >&2 "\
Use: local-cluster.sh CLUSTER ACTION $@

Orchestrator scripts to either create a new cluster, install its dependencies or cleans
them up.

This installs the required dependencies so we can install the various swh charts
(cluster-components, swh) within the local cluster.

help: This help message
CLUSTER: the cluster context (e.g. kind-local-cluster, swh-1, swh-2, ...)
ACTION: create|install-deps|cleanup-deps|pause|unpause|delete

"
}

case "$1" in
    -h|--help|help)
        usage && exit 0
        ;;
    *)
        ;;
esac

CLUSTER_CONTEXT=${1-kind-local-cluster}

case "$2" in
    -h|--help|help)
        usage && exit 0
        ;;
    create)
        bin/local-cluster-create.sh $CLUSTER_CONTEXT
        ;;
    restart)
        bin/local-cluster-restart.sh $CLUSTER_CONTEXT
        ;;
    install-deps|install)
        bin/local-cluster-install-deps.sh $CLUSTER_CONTEXT
        ;;
    uninstall-deps|uninstall|cleanup|remove-deps|uninstall-deps)
        bin/local-cluster-cleanup-deps.sh $CLUSTER_CONTEXT
        ;;
    delete)
        bin/local-cluster-delete.sh $CLUSTER_CONTEXT
        ;;
    pause)
        bin/local-cluster-pause.sh $CLUSTER_CONTEXT
        ;;
    unpause)
        bin/local-cluster-unpause.sh $CLUSTER_CONTEXT
        ;;
    *)
        echo "Unknown action <$1>: do nothing"
        ;;
esac
