
Execute following commands to start cluster from scratch:
```bash
./5751/configure-openbao-cluster.sh --reset
./5751/configure-vso-cluster.sh --reset
./5751/create-vso-secret.sh
```

Then:
* Configure your local /etc/hosts to access OpenBAO instance through ingress load balancer IP
```
echo "172.18.255.0 openbao.local" | sudo tee -a /etc/hosts
```
* [connect to ui](http://openbao.local:8200/) with token `root`
    * select `demo-mount`
    * create secret into `demo-app/config`
```bash
bao write demo-mount/demo-app/config _raw='{"data": {"username": "demo-user", "password": "demo-pass"}}'
```
* wait a few seconds, then look for k8s secret `demo-secret` in namespace `demo-app`, it should match the value you put into secret
```bash
$KUBECTL get secret 'demo-secret' -n 'app' -o json | jq -r '.data._raw' | base64 --decode | jq '.data'
```
