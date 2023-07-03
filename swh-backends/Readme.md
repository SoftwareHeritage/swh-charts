# What ?
Bootstrap all the necessary components to run the swh stack in a local cluster

# How ?

- Download the chart dependencies
```
helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add kedacore https://kedacore.github.io/charts
helm repo add elastic https://helm.elastic.co
helm repo update
cd swh-backends/
helm dependency build
```

- Apply the prometheus operator crds
```
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagerconfigs.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagers.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_probes.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusagents.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_scrapeconfigs.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.66.0/example/prometheus-operator-crd/monitoring.coreos.com_thanosrulers.yaml
```

- Deploy the base components
```
helm upgrade --install swh-backends  . -f values/step1.yaml
```

- Deploy the cassandra-operator
```
helm upgrade --install swh-backends  . -f values/step1.yaml -f values/step2.yaml
```

- Deploy cassandra
```
helm upgrade --install swh-backends . -f values/step1.yaml -f values/step2.yaml -f values/step3.yaml
```

- Deploy ELK
```
helm upgrade --install elk . -f values/elasticsearch.yaml
```

- Deploy swh
```
cd ../swh/
helm upgrade --install swh . --values values.yaml \
  --values values/minikube.yaml \
  --values ../values-swh-application-versions.yaml
```
