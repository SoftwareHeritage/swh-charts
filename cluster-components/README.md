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

This requires the cattle-monitoring-system namespace.

```
kubectl create namespace cattle-monitoring-system
```
