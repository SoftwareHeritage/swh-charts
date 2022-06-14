network
-------

This contains tools to check the network communication in the cluster is ok.

```
$ kubectl create -f overlay-test.yml
$ kubectl rollout status ds/overlaytest -w
# ^ wait until daemon set "overlaytest" successfully rolled out.
$ ./test-internode-communication.sh
# If no FAIL within the output log, then everything is fine
$ kubectl delete -f overlay-test.yml
```
```
source: https://rancher.com/docs/rancher/v2.5/en/troubleshooting/networking/

