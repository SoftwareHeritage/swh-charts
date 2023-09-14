IMAGE="helmunittest/helm-unittest:3.11.1-0.3.0"
# requires --user in the docker call to allow writing in the user's home
UID=1000
# This allows to introspect the swh/tests/__snapshot__/<generated-chart>.yaml
# output of the chart execution in the test context. It's in a dedicated
# target as this generates temporary files. This is to be used exceptionally
# to ease troubleshooting
ACTIVATE_SNAPSHOT=--update-snapshot
SWH_CHART=swh

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
      -n swh --create-namespace --debug

swh-uninstall:
	helm --kube-context minikube uninstall $(SWH_CHART) -n swh

swh-template:
	helm template $chart $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/minikube.yaml \
      -n swh --create-namespace --debug
