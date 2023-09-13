# Software Heritage stack helm chart
## Tests

The test are done with:
* [helm-unittest](https://github.com/helm-unittest/helm-unittest)
* [https://hub.docker.com/r/helmunittest/helm-unittest](https://hub.docker.com/r/helmunittest/helm-unittest)

For a run in docker, run this command:

```
docker run -ti --user $(id -u) --rm -v $(pwd):/apps helmunittest/helm-unittest --color --debug .
```

Expected output:

```

### Chart [ software-stories ] .

 PASS  test software-stories deployment tests/deployment_test.yaml
 PASS  test software-stories ingress    tests/ingress_test.yaml
 PASS  test software-stories service    tests/service_test.yaml

Charts:      1 passed, 1 total
Test Suites: 3 passed, 3 total
Tests:       3 passed, 3 total
Snapshot:    0 passed, 0 total
Time:        3.844307ms

```

## minikube

You can run the software-stories on minikube with the following command:

```
chart=software-stories; helm upgrade --install $chart $chart/ \
  --values values-swh-application-versions.yaml \
  --values $chart/values.yaml \
  --values $chart/values/minikube.yaml \
   -n software-stories \
   --create-namespace
```

Then in your /etc/hosts, reference:

```
192.168.49.2 fake-software-storage.i.s.s.n
```

Finally open your browser to https://fake-software-storage.i.s.s.n to enjoy the
software-stories application.
