#!/bin/bash

kubectl --context kind-local-cluster-vso apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: test
  namespace: app
---
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
  namespace: app
  annotations:
    kubernetes.io/service-account.name: test
type: kubernetes.io/service-account-token
EOF


-----BEGIN CERTIFICATE-----
MIIDBTCCAe2gAwIBAgIIW9g+5zc8mEowDQYJKoZIhvcNAQELBQAwFTETMBEGA1UE
AxMKa3ViZXJuZXRlczAeFw0yNjAxMjMwODI3NDRaFw0zNjAxMjEwODMyNDRaMBUx
EzARBgNVBAMTCmt1YmVybmV0ZXMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
AoIBAQDJ/6paT7hJqyNZ7oH1ilaBtw737eqV5ZZX3GG5sGBY2WLjGrG5sCicX4bB
gW5lb5X4c+pzYj5Derwvbs0zur36fmDA1fYalePnJN8JNZnqe4Lwpaq5Uzj2fAxa
wy7cdDiSeKyXd6BZqMNSO+jdi//tU5dH/qyOx3H2DqYyG4SOo7yTr1p5XtbHXRT6
VZDZNcU7L85O5dsjtTfObK1Eq5x4457oi7iKHSR+3AMWxisH5wBIMDjaC91VCWlg
hiE37kg6gMU3QrgMpLQG3W662EbGsg86+sK4FmXZ1PE+l7Ea7hOTF0WDZv90sgDn
fXioBe1XPmwP9cyvdEJMV8QbagZfAgMBAAGjWTBXMA4GA1UdDwEB/wQEAwICpDAP
BgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTteAyzpGBbpzX/vQW20OyCRpFY/TAV
BgNVHREEDjAMggprdWJlcm5ldGVzMA0GCSqGSIb3DQEBCwUAA4IBAQCTQb7doTaz
nAxixQN9BdPRrrZ2B18qj3oXIOLT92N3w8YvAI0uxQURJ0y8f6e6aSCcqFVczvJu
xaNILvn0I2tIJTLkVdYAyR14JESnQjREw9B8B15jD+pPT8NR705J53M+Dv39xpVR
dF/Hp0ENwv3GsDQsZXFd1qPS3kWhdm+ms5lg06rx1KlFbr2jhQ6lPZ7TA6twgncH
GF0/VdGT8ZXuWkl7juTSQU2A5LJXzmnzaDK5bcmmyJIw4JI5zxAMfDdyUVRn3lyG
nhoyk4JCDhFqtjwkoGrsD8B69l0oPtNtbdLjZka/hldmQWcI24dAvPIiQKI9L+hf
PpS7TDNYZCfz
-----END CERTIFICATE-----
