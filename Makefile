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
CCF_CHART=cluster-configuration
SS_CHART=software-stories

# For sandboxed environment
LOCAL_CLUSTER_CONTEXT=minikube
# (deprecated) Retro-compatible name
MINIKUBE_CONTEXT=$(LOCAL_CLUSTER_CONTEXT)

CC_LOCAL_OVERRIDE=minikube-cc.override.yaml
SWH_LOCAL_OVERRIDE=minikube-swh.override.yaml

ifeq (,$(wildcard $(CC_LOCAL_OVERRIDE)))
  CC_VALUES_OVERRIDE := --debug
else
  CC_VALUES_OVERRIDE := --values $(CC_LOCAL_OVERRIDE)
endif

ifeq (,$(wildcard $(SWH_LOCAL_OVERRIDE)))
  SWH_VALUES_OVERRIDE := --debug
else
  SWH_VALUES_OVERRIDE := --values $(SWH_LOCAL_OVERRIDE)
endif

# use: make VERBOSE=1 to actually have the command displayed
ifndef VERBOSE
.SILENT:
endif

local-cluster-create:
	bin/local-cluster.sh $(LOCAL_CLUSTER_CONTEXT) create

local-cluster-install-deps:
	bin/local-cluster.sh $(LOCAL_CLUSTER_CONTEXT) install-deps

local-cluster-restart:
	bin/local-cluster.sh $(LOCAL_CLUSTER_CONTEXT) restart

local-cluster-cleanup-deps:
	bin/local-cluster.sh $(LOCAL_CLUSTER_CONTEXT) cleanup-deps

local-cluster-delete:
	bin/local-cluster.sh $(LOCAL_CLUSTER_CONTEXT) delete

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
	./swh/helm-diff.sh

ccf-helm-diff:
	./helm-diff.sh cluster-configuration

cc-helm-diff:
	./helm-diff.sh cluster-components

ss-helm-diff:
	./helm-diff.sh software-stories

helm-diff: swh-helm-diff ccf-helm-diff cc-helm-diff ss-helm-diff

swh-minikube: swh-local
swh-local:
	kubectl --context $(LOCAL_CLUSTER_CONTEXT) create namespace swh ; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace swh apply -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    helm --kube-context $(LOCAL_CLUSTER_CONTEXT) upgrade --install $(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/minikube.yaml \
      $(SWH_VALUES_OVERRIDE) \
      -n swh --debug

swh-uninstall: swh-local-uninstall
swh-local-uninstall:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) uninstall $(SWH_CHART) -n swh ; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace swh delete -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) delete namespace swh

swh-template:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/minikube.yaml \
      $(SWH_VALUES_OVERRIDE) \
      -n swh --create-namespace --debug

swh-template-staging:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/default.yaml \
      --values $(SWH_CHART)/values/staging/default.yaml \
      --values $(SWH_CHART)/values/staging/swh.yaml \
      -n swh --create-namespace --debug

swh-template-staging-cassandra:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/default.yaml \
      --values $(SWH_CHART)/values/staging/default.yaml \
      --values $(SWH_CHART)/values/staging/swh-cassandra.yaml \
      -n swh --create-namespace --debug

swh-template-staging-cassandra-next-version:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/default.yaml \
      --values $(SWH_CHART)/values/staging/default.yaml \
      --values $(SWH_CHART)/values/staging/swh-cassandra.yaml \
      --values $(SWH_CHART)/values/staging/overrides/swh-cassandra-next-version.yaml \
      -n swh --create-namespace --debug

swh-template-production:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/default.yaml \
      --values $(SWH_CHART)/values/production/default.yaml \
      --values $(SWH_CHART)/values/production/swh.yaml \
      -n swh --create-namespace --debug

swh-template-production-cassandra:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/default.yaml \
      --values $(SWH_CHART)/values/production/default.yaml \
      --values $(SWH_CHART)/values/production/swh-cassandra.yaml \
      -n swh --create-namespace --debug

cc-minikube: cc-local
cc-local:
	kubectl --context $(LOCAL_CLUSTER_CONTEXT) create namespace cluster-components; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) create namespace swh; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace cluster-components apply -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace swh apply -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    helm --kube-context $(LOCAL_CLUSTER_CONTEXT) upgrade --install $(CC_CHART) $(CC_CHART)/ \
      --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/minikube.yaml \
      $(CC_VALUES_OVERRIDE) \
      --namespace cluster-components --create-namespace --debug

cc-uninstall:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) uninstall $(CC_CHART) --namespace cluster-components; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace cluster-components delete -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) delete namespace cluster-components

cc-template:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/minikube.yaml \
      $(CC_VALUES_OVERRIDE) \
      --namespace cluster-components --create-namespace --debug

cc-template-test-staging-rke2:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/default.yaml \
      --values $(CC_CHART)/values/test-staging-rke2.yaml \
      --debug

cc-template-staging:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/default.yaml \
      --values $(CC_CHART)/values/archive-staging-rke2.yaml \
      --debug

cc-template-production:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/default.yaml \
      --values $(CC_CHART)/values/archive-production-rke2.yaml \
      --debug

cc-template-admin:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/default.yaml \
      --values $(CC_CHART)/values/admin-rke2.yaml \
      --debug

ccf-template-admin-rke2:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/admin-rke2.yaml \
      -n default --create-namespace --debug

ccf-template-archive-production-rke2:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/archive-production-rke2.yaml \
      --debug

ccf-template-archive-staging-rke2:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/archive-staging-rke2.yaml \
      --debug

ccf-template-gitlab-production:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/gitlab-production.yaml \
      --debug

ccf-template-gitlab-staging:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/gitlab-staging.yaml \
      --debug

ccf-template-rancher:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/rancher.yaml \
      --debug

ccf-template-test-staging-rke2:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/test-staging-rke2.yaml \
      --debug

ss-minikube: ss-local
ss-local:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) upgrade --install $(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/minikube.yaml \
      -n software-stories --create-namespace --debug

ss-uninstall:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) uninstall $(SS_CHART) -n software-stories

ss-template:
	helm template template-$(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/minikube.yaml \
      -n software-stories --create-namespace --debug

ss-template-staging:
	helm template template-$(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/staging.yaml

ss-template-production:
	helm template template-$(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/production.yaml
