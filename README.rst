swh-charts
==========

Helm charts for the swh infrastructure.

It's composed of multiple helm charts:

- swh: the swh stack (e.g. rpc services, loader, lister, cooker, ...)
  - storage-replayer
  - statsd-exporter
  - loaders: various loaders
  - listers: various listers
  - graphql: graphql rpc service
  - storage: storage rpc service
    indexers: indexer storage rpc service
    indexer: indexers journal clients
    search: search rpc service
  - ...

- cluster-components: tools (e.g. alerting, monitoring, backends, ...) to run in
                      cluster environments
  - alertmanager-irc-relay
  - blackbox-exporter
    postgresql cluster(s)
    kafka cluster(s)
  - ...

- cluster-configuration: tool dependencies (e.g. operator) to install in
                         cluster environments
   - cert-manager
   - ingress-nginx
   - metallb
   - otlp-collector
     cloudnative-pg operator
     kafka operator
   - ...

Those charts rely on secrets which are installed through other applications
(relying on the "k8s-private-data" private repository).
