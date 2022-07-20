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
swh-charts/swh-graphql $ helm install -f my-values.yaml graphql .
```

With `my-values.yaml`  containing some overrides of the default
values matching your environment.

What's currently deployed can be seen with:

```
swh-charts/swh-graphql $ helm list
NAME    NAMESPACE       REVISION        UPDATED                                         STATUS          CHART                   APP VERSION
graphql default         1               2022-07-20 10:40:21.405492989 +0200 CEST        deployed        swh-graphql-0.1.0       1.16.0

```

Possible values can be listed too:
```
swh-charts/swh-graphql $ helm show values .
```
