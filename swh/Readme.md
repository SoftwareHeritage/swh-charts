# Software Heritage stack helm chart
## Tests

The test are done with [helm-unittest](https://github.com/quintush/helm-unittest)

helm-unit can be launched in docker or used as a [helm plugin](https://github.com/quintush/helm-unittest#install).


For a run in docker, run this command:

```
docker run -ti --rm -v $(pwd)/..:/apps quintush/helm-unittest:3.11.1-0.3.0  --color --debug swh
```

warning: It tests the helm chart behavior, not the descriptors are valid for kubernetes

Example of outputs:
```
docker run -ti --rm -v $(pwd)/..:/apps quintush/helm-unittest:3.11.1-0.3.0  --color --debug swh

### Chart [ Argocd applications commonly used in to configure a SWH cluster ] .

 PASS  test cluster configuration application   tests/basic-applications_test.yaml
 PASS  test cluster metallb application tests/metallb-application_test.yaml


### Chart [ swh ] swh

 PASS  test graphql deployment  swh/tests/graphql_configmap_test.yaml
 PASS  test graphql deployment  swh/tests/graphql_deployment_test.yaml
 PASS  test graphql deployment  swh/tests/graphql_global_test.yaml
 PASS  test graphql deployment  swh/tests/graphql_service_test.yaml

Charts:      1 passed, 1 total
Test Suites: 4 passed, 4 total
Tests:       9 passed, 9 total
Snapshot:    0 passed, 0 total
Time:        29.410877ms
```
