swh-charts
==========

Helm charts for the swh infrastructure.

It's composed of multiple helm charts:

- swh: swh rpc services and workers:
  - storage-replayer
  - statsd-exporter
  - loaders: various loaders
  - listers: various listers
  - graphql: graphql rpc service
  - storage: storage rpc service
  - ...

- cluster-components: tools (alerting, monitoring) to run in cluster environments
  - alertmanager-irc-relay
  - blackbox-exporter
  - ...

- cluster-configuration: (deprecated) tools to run in cluster environments
   - cert-manager
   - ingress-nginx
   - metallb
   - otlp-collector
   - ...

