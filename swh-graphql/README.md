# Goal

- Deploy a standalone graphql instance

This chart will be merged with the global swh chart when available

# helm

We use helm to ease the cluster application management.

# Install

## Prerequisites
- Helm >= 3.0
- Access to a kubernetes cluster
- The url of a reachable swh storage

## Chart installation

Install the worker declaration from this directory in the cluster
```
$ helm install -f my-values.yaml graphql
```

With `my-values.yaml`  containing some overrides of the default
values matching your environment.

Detail of the possible values is visible with:
```
swh-charts/swh-graphql $ helm show values . 
```
