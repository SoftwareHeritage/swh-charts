IMAGE="helmunittest/helm-unittest:3.11.1-0.3.0"
# requires --user in the docker call to allow writing in the user's home
UID=1000
# This allows to introspect the swh/tests/__snapshot__/<generated-chart>.yaml
# output of the chart execution in the test context. It's in a dedicated
# target as this generates temporary files. This is to be used exceptionally
# to ease troubleshooting
ACTIVATE_SNAPSHOT=--update-snapshot
SWH_CHART=swh
CC_CHART=cluster-components
SS_CHART=software-stories

swh-test:
	docker run -ti --user $(UID) --rm -v $(PWD):/apps \
	  $(IMAGE) swh

swh-test-with-snapshot:
	docker run -ti --user $(UID) --rm -v $(PWD):/apps \
	  $(IMAGE) $(ACTIVATE_SNAPSHOT) swh

ss-test:
	docker run -ti --user $(UID) --rm -v $(PWD):/apps \
	  $(IMAGE) software-stories

ss-test-with-snapshot:
	docker run -ti --user $(UID) --rm -v $(PWD):/apps \
	  $(IMAGE) $(ACTIVATE_SNAPSHOT) software-stories


swh-helm-diff:
	./helm-diff.sh swh

cc-helm-diff:
	./helm-diff.sh cluster-configuration

ss-helm-diff:
	./helm-diff.sh software-stories

helm-diff: swh-helm-diff cc-helm-diff ss-helm-diff

swh-minikube:
	helm --kube-context minikube upgrade --install $(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/minikube.yaml \
      -n swh --create-namespace --debug && \
    kubectl --context minikube apply -f '$(SWH_CHART)/fake-secrets/*.yaml'

swh-uninstall:
	helm --kube-context minikube uninstall $(SWH_CHART) -n swh && \
    kubectl --context minikube --namespace swh delete -f '$(SWH_CHART)/fake-secrets/*.yaml'

swh-template:
	helm template $chart $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/minikube.yaml \
      -n swh --create-namespace --debug

cc-minikube:
	helm --kube-context minikube upgrade --install $(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/minikube.yaml \
      -n default --create-namespace --debug

cc-uninstall:
	helm --kube-context minikube uninstall $(CC_CHART) -n default

cc-template:
	helm template $chart $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/minikube.yaml \
      -n default --create-namespace --debug

ss-minikube:
	helm --kube-context minikube upgrade --install $(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/minikube.yaml \
      -n software-stories --create-namespace --debug

ss-uninstall:
	helm --kube-context minikube uninstall $(SS_CHART) -n software-stories

ss-template:
	helm template $chart $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/minikube.yaml \
      -n software-stories --create-namespace --debug
