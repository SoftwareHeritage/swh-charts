IMAGE="helmunittest/helm-unittest:3.11.1-0.3.0"
# requires --user in the docker call to allow writing in the user's home
UID=1000
# This allows to introspect the swh/tests/__snapshot__/<generated-chart>.yaml
# output of the chart execution in the test context. It's in a dedicated
# target as this generates temporary files. This is to be used exceptionally
# to ease troubleshooting
ACTIVATE_SNAPSHOT=--update-snapshot

test:
	docker run -ti --user $(UID) --rm -v $(PWD):/apps \
	  $(IMAGE) swh

test-with-snapshot:
	docker run -ti --user $(UID) --rm -v $(PWD):/apps \
	  $(IMAGE) $(ACTIVATE_SNAPSHOT) swh
