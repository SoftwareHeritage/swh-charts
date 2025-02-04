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

DIFF_COMMAND=auto
SECRET_FILES='$(SWH_CHART)/fake-secrets'

# For sandboxed environment
LOCAL_CLUSTER_ENVIRONMENT=kind
LOCAL_CLUSTER_CONTEXT=kind-local-cluster
# You can chose to use minikube
# LOCAL_CLUSTER_ENVIRONMENT=minikube
# LOCAL_CLUSTER_CONTEXT=$(LOCAL_CLUSTER_ENVIRONMENT)

# (deprecated) Retro-compatible name
MINIKUBE_CONTEXT=$(LOCAL_CLUSTER_CONTEXT)

CC_LOCAL_OVERRIDE=local-cluster-cc.override.yaml
SWH_LOCAL_OVERRIDE=local-cluster-swh.override.yaml
CCF_LOCAL_OVERRIDE=local-cluster-ccf.override.yaml

ifeq (,$(wildcard $(CCF_LOCAL_OVERRIDE)))
  CCF_VALUES_OVERRIDE := --debug
else
  CCF_VALUES_OVERRIDE := --values $(CCF_LOCAL_OVERRIDE)
endif

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

-include Makefile.local

local-cluster-create:
	bin/local-cluster.sh create $(LOCAL_CLUSTER_CONTEXT) $(LOCAL_CLUSTER_ENVIRONMENT)

local-cluster-install-deps:
	bin/local-cluster.sh install-deps $(LOCAL_CLUSTER_CONTEXT) $(LOCAL_CLUSTER_ENVIRONMENT)

local-cluster-restart:
	bin/local-cluster.sh restart $(LOCAL_CLUSTER_CONTEXT)

local-cluster-cleanup-deps:
	bin/local-cluster.sh cleanup-deps $(LOCAL_CLUSTER_CONTEXT)

local-cluster-pause:
	bin/local-cluster.sh pause $(LOCAL_CLUSTER_CONTEXT) $(LOCAL_CLUSTER_ENVIRONMENT)

local-cluster-unpause:
	bin/local-cluster.sh unpause $(LOCAL_CLUSTER_CONTEXT) $(LOCAL_CLUSTER_ENVIRONMENT)

local-cluster-delete:
	bin/local-cluster.sh delete $(LOCAL_CLUSTER_CONTEXT)

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
	./swh/helm-diff.sh production $(DIFF_COMMAND)

ccf-helm-diff:
	./helm-diff.sh $(CCF_CHART) $(DIFF_COMMAND)

cc-helm-diff:
	./helm-diff.sh $(CC_CHART) $(DIFF_COMMAND)

ss-helm-diff:
	./helm-diff.sh $(SS_CHART) $(DIFF_COMMAND)

helm-diff: swh-helm-diff ccf-helm-diff cc-helm-diff ss-helm-diff

local-cluster-swh-prepare:
	kubectl --context $(LOCAL_CLUSTER_CONTEXT) get namespace swh 2>&1 >/dev/null || \
      kubectl --context $(LOCAL_CLUSTER_CONTEXT) create namespace swh

local-cluster-swh-prepare-secrets:
	cat $(SECRET_FILES)/*.yaml | kubectl --context $(LOCAL_CLUSTER_CONTEXT) \
        --namespace swh apply -f -

swh-minikube: swh-local-cluster
local-cluster-swh: swh-local-cluster
swh-local-cluster: local-cluster-swh-prepare local-cluster-swh-prepare-secrets
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) upgrade --install $(SWH_CHART) $(SWH_CHART) \
      --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/local-cluster.yaml \
      $(SWH_VALUES_OVERRIDE) \
      -n swh --debug

swh-uninstall: swh-local-cluster-uninstall
local-cluster-uninstall-swh: swh-local-cluster-uninstall
swh-local-cluster-uninstall:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) uninstall $(SWH_CHART) -n swh ; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace swh delete -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) delete namespace swh

swh-template:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/local-cluster.yaml \
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

swh-template-staging-cassandra-next-version: swh-template-staging-next-version

swh-template-staging-next-version:
	helm template template-$(SWH_CHART) $(SWH_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SWH_CHART)/values.yaml \
      --values $(SWH_CHART)/values/default.yaml \
      --values $(SWH_CHART)/values/staging/default.yaml \
      --values $(SWH_CHART)/values/staging/next-version.yaml \
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

local-cluster-cc-prepare:
	kubectl --context $(LOCAL_CLUSTER_CONTEXT) get namespace cluster-components 2>&1 >/dev/null || \
      kubectl --context $(LOCAL_CLUSTER_CONTEXT) create namespace cluster-components

local-cluster-cc-prepare-secrets:
	cat $(SECRET_FILES)/*.yaml | kubectl --context $(LOCAL_CLUSTER_CONTEXT) \
        --namespace cluster-components apply -f -

cc-minikube: cc-local-cluster
local-cluster-cc: cc-local-cluster
cc-local-cluster: local-cluster-cc-prepare local-cluster-swh-prepare local-cluster-cc-prepare-secrets local-cluster-swh-prepare-secrets
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) upgrade --install $(CC_CHART) $(CC_CHART)/ \
      --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/local-cluster.yaml \
      $(CC_VALUES_OVERRIDE) \
      --namespace cluster-components --create-namespace --debug

cc-uninstall: cc-local-cluster-uninstall
local-cluster-uninstall-cc: cc-local-cluster-uninstall
cc-local-cluster-uninstall:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) uninstall $(CC_CHART) --namespace cluster-components; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) --namespace cluster-components delete -f '$(SWH_CHART)/fake-secrets/*.yaml'; \
    kubectl --context $(LOCAL_CLUSTER_CONTEXT) delete namespace cluster-components

cc-template:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/local-cluster.yaml \
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

cc-template-staging-next-version:
	helm template template-$(CC_CHART) $(CC_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CC_CHART)/values.yaml \
      --values $(CC_CHART)/values/default.yaml \
      --values $(CC_CHART)/values/archive-staging-rke2-next-version.yaml \
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

ccf-template:
	helm template template-$(CCF_CHART) $(CCF_CHART)/ --values values-swh-application-versions.yaml \
      --values $(CCF_CHART)/values.yaml \
      --values $(CCF_CHART)/values/local-cluster.yaml \
      $(CCF_VALUES_OVERRIDE) \
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

ss-minikube: ss-local-cluster
ss-local-cluster:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) upgrade --install $(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/local-cluster.yaml \
      -n software-stories --create-namespace --debug

ss-uninstall: ss-local-cluster-uninstall
local-cluster-uninstall-ss: ss-local-cluster-uninstall
ss-local-cluster-uninstall:
	helm --kube-context $(LOCAL_CLUSTER_CONTEXT) uninstall $(SS_CHART) -n software-stories

ss-template:
	helm template template-$(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/local-cluster.yaml \
      -n software-stories --create-namespace --debug

ss-template-staging:
	helm template template-$(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/staging.yaml

ss-template-production:
	helm template template-$(SS_CHART) $(SS_CHART)/ --values values-swh-application-versions.yaml \
      --values $(SS_CHART)/values.yaml \
      --values $(SS_CHART)/values/production.yaml
