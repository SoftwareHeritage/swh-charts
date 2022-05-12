# Goal

- autoscaling workers depending on repositories to load and allocated resources.

# keda

This uses KEDA - K(ubernetes) E(vents)-D(riven) A(utoscaling):
```
$ helm repo add kedacore https://kedacore.github.io/charts
$ helm repo update
swhworker@poc-rancher:~$ kubectl create namespace keda
namespace/keda created
swhworker@poc-rancher:~$ helm install keda kedacore/keda --namespace keda
NAME: keda
LAST DEPLOYED: Fri Oct  8 09:48:40 2021
NAMESPACE: keda
STATUS: deployed
REVISION: 1
TEST SUITE: None
```
source: https://keda.sh/docs/2.4/deploy/

# helm

We use helm to ease the cluster application management.

# Install

Install the worker declaration from this directory in the cluster
```
$ export KUBECONFIG=export KUBECONFIG=staging-workers.yaml
$ TYPE=git; REL=workers-$TYPE; \
  helm install -f ./loader-$TYPE.staging.values.yaml $REL ../worker
$ TYPE=pypi; REL=workers-$TYPE; \
  helm install -f ./loader-$TYPE.staging.values.yaml $REL ../worker
```

Where:
```
$ cat ../loader-git.staging.values.yaml
# Default values for worker.
# This is a YAML-formatted file.
# Declare variables to be passed into your templates.

amqp:
  host: scheduler0.internal.staging.swh.network
  queue_threshold: 10  # spawn worker per increment of `value` messages
  queues:
      - swh.loader.git.tasks.UpdateGitRepository
      - swh.loader.git.tasks.LoadDiskGitRepository
      - swh.loader.git.tasks.UncompressAndLoadDiskGitRepository

storage:
  host: storage1.internal.staging.swh.network

loader:
  name: loaders
  type: git
```

# List

List currently deployed applications:

```
$ helm list
helm list
NAME            NAMESPACE       REVISION        UPDATED                                         STATUS          CHART           APP VERSION
workers-bzr     default         1               2022-04-29 12:59:32.111950055 +0200 CEST        deployed        worker-0.1.0    1.16.0
workers-git     default         4               2022-04-29 12:50:12.322826487 +0200 CEST        deployed        worker-0.1.0    1.16.0
workers-pypi    default         1               2022-04-29 12:51:22.506259018 +0200 CEST        deployed        worker-0.1.0    1.16.0
```

# Upgrade

When adapting the worker definition, you can apply the changes by upgrading the
deployed application:

```
$ TYPE=git; REL=workers-$TYPE; \
  helm upgrade -f ./loader-$TYPE.staging.values.yaml $REL ../worker
```

# Secrets

The current work requires credentials (installed as secret within the cluster):
- metadata fetcher credentials `metadata-fetcher-credentials`
- amqp credentials ``

More details describing the secrets:
```
$ kubectl describe secret metadata-fetcher-credentials
```

Installed through:

```
$ TYPE=git  # Replace mentions below in the yaml files
$ kubectl -f $SECRET_FILE apply --namespaces ns-loader-$TYPE
# for secret file in {
# instances/loaders-$TYPE-metadata-fetcher-credentials.secret.yaml
# ./loader-$TYPE-sentry.secret.yaml
# ./amqp-access-credentials.secret.yaml
# ...
# }
$ cat instances/loaders-metadata-fetcher.secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: metadata-fetcher-credentials
type: Opaque
stringData:
  data: |
    metadata_fetcher_credentials:
      github:
        github:
        - username: <redacted>
          password: <redacted>
        - ...
$ cat ./amqp-access-credentials.secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: amqp-access-credentials
  namespace: ns-loaders-$TYPE
type: Opaque
stringData:
  host: amqp://<redacted>:<redacted>@scheduler0.internal.staging.swh.network:5672/%2f
$ cat ./loaders-$TYPE-sentry.secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: loaders-$TYPE-sentry-secrets
  namespace: ns-loaders-$TYPE
type: Opaque
stringData:
  sentry-dsn: https://<redacted>@sentry.softwareheritage.org/8
```
