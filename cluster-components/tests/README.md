# Start the minikube cluster
```
# Start
minikube start
cd cluster-components
# install
helm install cluster-components . --values values.yaml --values values/minikube.yaml
# install or upgrade
# helm install --upgrade cluster-components . --values values.yaml --values values/minikube.yaml
# wait for all things to be running
```

Then trigger a fake alert on the irc channel:
```
# port forward the alertmanager-irc-relay
# Then, trigger a fake alert
curl -d @data.json http://127.0.0.1:8000/minikube-swh-sysadm
```
