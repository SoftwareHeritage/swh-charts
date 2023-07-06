# What ?
Bootstrap all the necessary components to run the swh stack in a local cluster

# How ?

- Download the chart dependencies
```
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add elastic https://helm.elastic.co
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add kedacore https://kedacore.github.io/charts
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
cd swh-backends/
helm dependency build
for ns in swh elastic otlp; do kubectl create namespace $ns; done
```

- Deploy the base components
```
helm --namespace swh upgrade --install swh-backends  . -f values/step1.yaml
```

- Deploy the operators
```
helm --namespace swh upgrade --install swh-backends  . -f values/step1.yaml -f values/step2.yaml
```

- Deploy tools (cassandra, rabbitmq, ...)
```
helm --namespace swh upgrade --install swh-backends . -f values/step1.yaml -f values/step2.yaml -f values/step3.yaml
```

- Deploy ELK
```
helm --namespace elastic upgrade --install elk . --values values/elasticsearch-step1.yaml
helm --namespace elastic upgrade --install elk . \
    --values values/elasticsearch-step1.yaml \
    --values values/elasticsearch-step2.yaml
```

- Deploy swh
```
cd ../swh/
helm --namespace swh upgrade --install swh . --values values.yaml \
  --values ../values-swh-application-versions.yaml \
  --values values/minikube.yaml
```

- Deploy opentelemetry cluster configuration
```
cd ../swh-backends
helm --namespace otlp install otlp . \
  --values values.yaml \
  --values values/otlp-collector.yaml
```
