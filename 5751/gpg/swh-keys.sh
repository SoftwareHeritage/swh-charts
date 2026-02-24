#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBKEYS_DIR="$SCRIPT_DIR/pubkeys"

gpg --export 293120CE3A5A539098EC8BFCFCCAC3BE39CB12D3 | base64 > "${PUBKEYS_DIR}/dicosmo.asc"
gpg --export 4900707DDC5C07F2DECB02839C31503C6D866396 | base64 > "${PUBKEYS_DIR}/zacchiroli.asc"
gpg --export 6F339C5E1725D5E379100F096F31F7545A885252 | base64 > "${PUBKEYS_DIR}/dandrimont.asc"
gpg --export BF00203D741AC9D546A8BE0752E2E9840D10C3B8 | base64 > "${PUBKEYS_DIR}/dumont.asc"
gpg --export 7DC7325EF1A6226AB6C3D7E32388A3BF6F0A6938 | base64 > "${PUBKEYS_DIR}/douard.asc"
gpg --export 1D5B70091CDAC0B9E3F634B7B680FC7EE092A2E3 | base64 > "${PUBKEYS_DIR}/deregnaucourt.asc"

POD_DATA_DIR=/openbao/data
POD_PUBKEYS_DIR=${POD_DATA_DIR}/pubkeys

NS_OPENBAO=openbao
KUBECTL_ADMIN="kubectl --context kind-local-cluster-admin"
POD_NAME=$($KUBECTL_ADMIN get pods -n "${NS_OPENBAO}" -l app.kubernetes.io/name=openbao -o jsonpath="{.items[0].metadata.name}")

${KUBECTL_ADMIN} cp "${PUBKEYS_DIR}"/ "${NS_OPENBAO}/${POD_NAME}:${POD_DATA_DIR}/"
${KUBECTL_ADMIN} exec "${POD_NAME}" -n "${NS_OPENBAO}" -- /bin/sh -c "bao operator init -key-shares=2 -key-threshold=2 -pgp-keys=${POD_PUBKEYS_DIR}/deregnaucourt.asc,${POD_PUBKEYS_DIR}/dumont.asc"

#Unseal Key 1: wcDMAwJCrAavvzaxAQv7B6xIOIEwnTO/1cWtjtpoPuiIao9wS2aZCDQbNcIM5L+1TBVGRckqYmJygdffZ2OYf+LVMcWx7zJgSbl1LN56PVhMoo5Vjcg7v1UkZywMWCXj/dankn7TjzCvsOY0gUObn09EvDir5qWRab8kvNuRW5ZYB43AZYx8CpArz9Yt6ew9TWcbRdKSpBr0HPYXj1nLxMwFp1Ec4WxfnhOGbjCSnJonlC/8eJrw4fDeyJbQzgCAyYY6weVN/379XruW2vzzzpFojrnmK3XnVZcXtIfYTcdebQXoEmH8Fg1vsvQE89/egVPTOrI1Tl4rUZtbBzt+pJqBZyYmXTw99Pz0g0TznKWTEABJBiO8kISR0JFIEdLZnnHs43whCKmWthz6vropWci1UVWvi6jpBtUGCgkwVA/xHSUnvMcsRI4G5ebtLzQrlohuENTell7BBCs7qjDrqszjaUwktC+ggtTaa02JzS8v+Hmo1wkrboHRkOebnDCnkv0YdadX4aINJ1mpCIZa0nMBIYU/1vZwKe3iKsoqAs2yh3g33PEcr4nuJP+tmbIh/ZN60ikMN8RtdNGXFRXnQAskDu6aGRQ5JoIIRqMLDoF1HAubkIObysxxpiW5PZkOeyR/HtmmpNkpTGjCBJOQSoistn3Te68SZHTImnw1T9Vbre+r
#Unseal Key 2: wcFMA81lqryHorhFAQ/6A+U6ZJJAVUKCHL6+7+H/FpxNU+LJaLoNsIi/iFc9rguZFmFeudLeejBAG+iJCOGEMxC2lwIXvULATKpQtQChkwBHTqsCIN3g/rbDTJYb1/SJ1pl8EPw4RdqdnMFfMWHydjRbgb14C58NOefttREAoCGZ1ilwbm38rFeXhboOPP4MZH2cEorBYL8UmlP4LgiHK3QqYjoygqn0YNwnKo+WMrrCvpLechFa8Ej1g3rrCuJxcohSWHinoEij6uySdRuqddtnxgAjdZRncWLQco4hF9qAGGaVE8OP+5Xjd+8XU35JLAxhWfWCf3MQBosCFdYfPZfoZuDe0wdI26UGrPV/TVtMSBI6KxuCKpOhmFPPfFBAVlnmQvrq5tuqPzsu2Pfv/eD7Im6k2q24S0CgCJphLA4Fnm1EwkUXMTTHk7CJdpMo5JaAjF9Eizf2z6wFT/hUbDErIHjpS1VhuOcY8ukn95Gf/W46JMxpgHKTd4VQNYaFYL7WTSdsmhlHSF//j0rJr+dv0nktXl4EqM7mquWWQpSryuH+VKho1lk85E2ZYxgrUb6f2dbOZTYDmb1y9DkO5/Dvcxvez5lYvTJapO+q0fy/NmjHSHBqzTtrJ/J8aUW+Ux7w4jMBG2Lm8DdN/mu1A8QyQqtADo3VKZnHsegMPjrZoOwC15hX+TTV5eJz3FvScwGdZcVw/DntKEWAoDGnny/ElupZBOH6LeJ8eE4s5SJimaKwUy++AGKOot1grOwGIw3xQuoAoPKMhaMrIuc2FOfDezzph+3Ek5AWqlMpafmGZO5Yx20vyD5ayLpHzR/t2nVfy/GdvA3dCPZh8MnoJgTM0BI=
#
#Initial Root Token: s.WmcucMkW36Q5lltMzHfEtLfI
#
#Vault initialized with 2 key shares and a key threshold of 2. Please securely
#distribute the key shares printed above. When the Vault is re-sealed,
#restarted, or stopped, you must supply at least 2 of these keys to unseal it
#before it can start servicing requests.
#
#Vault does not store the generated root key. Without at least 2 keys to
#reconstruct the root key, Vault will remain permanently sealed!
#
#It is possible to generate new unseal keys, provided you have a quorum
#of existing unseal keys shares. See "bao operator rotate-keys" for more
#information.



# Log into openbao-0 and unseal vault:
# bao operator unseal

# Each key must be decrypted with GPG provate key:
# echo "base64-encoded-key-share" | base64 -d | gpg -dq
# db698df0223463e29e435700e1b3411339e6c3cac0b490bde435c1898488986399
# eda84dc9a201e06de3379316ddd23099da2f9e55b8ab8351471797a72bab65659a

# openbao-0 is now ready, and vault cluster is now available for other replicas to join.

# Connect to openbao-1, join raft cluster and unseal vault:
# Then join raft cluster with:
# bao operator raft join http://10.244.3.10:8200
# bao operator unseal

# etc.