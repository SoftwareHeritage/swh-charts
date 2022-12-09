# cluster configuration templates

## Tests

The test are done with [helm-unittest](https://github.com/quintush/helm-unittest)

helm-unit can be launch in docker or used as a [helm plugin](https://github.com/quintush/helm-unittest#install).


For a run in docker, run this command:

```
docker run -ti --rm -v $(pwd):/apps quintush/helm-unittest:3.10.1-0.2.10 -3  --color --debug .
```

warning: It tests the helm chart behavior, not the descriptors are valid for kubernetes

Example of outputs:
```
docker run -ti --rm -v $(pwd):/apps quintush/helm-unittest:3.10.1-0.2.10 -3  --color --debug .

### Chart [ Argocd applications commonly used in to configure a SWH cluster ] .

 PASS  test cluster configuration application   tests/basic-applications_test.yaml
 PASS  test cluster metallb application tests/metallb-application_test.yaml

Charts:      1 passed, 1 total
Test Suites: 2 passed, 2 total
Tests:       5 passed, 5 total
Snapshot:    0 passed, 0 total
Time:        9.683458ms
```
