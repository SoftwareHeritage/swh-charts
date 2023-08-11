# cluster components templates

This targets to declare appropriately cluster configuration. The previous version named
"cluster-configuration" should be deprecated in favor of this one.

The previous "cluster-configuration" (in the eponym folder) declares argocd
"applications" while it should not.

This one will limit itself to deploy deploy kubernetes "deployments". The argocd
application installation will stay within the scope of the "k8s-cluster-config"
repository. When the scaffolding will be in place, we'll have to refactor the old
cluster configuration within its scope.

Example of components:
- blackbox
- alertmanager-irc-relay
- nginx
- alerts
- ...

## minikube

This requires some steps to prepare the minikube cluster.

```
helm repo add bitnami https://charts.bitnami.com/bitnami
# helm repo add elastic https://helm.elastic.co
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
# helm repo add kedacore https://kedacore.github.io/charts
# helm repo add k8ssandra https://helm.k8ssandra.io/stable
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo add opentelemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
cd swh-backends/
helm dependency build

# Create the default namespace we deploy monitoring/alerting services
kubectl create namespace cattle-monitoring-system
# (Temporarily) Enable the ingress controller
minikube addons enable ingress
```
