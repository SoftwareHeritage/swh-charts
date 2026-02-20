#!/usr/bin/env bash
# -*- eval: (setq-default sh-indentation 2) -*-

# This script configures the targeted local cluster with vault-secrets-operator:
# * create `vso` and `app` namespaces
# * install vso helm chart inside `vso` namespace
# * configure vault auth from the targeted cluster in the openbao cluster

# This script does not create any secrets yet (see create-secret.sh)

set -e

TEMP_DIR=$(mktemp -d)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_FILE="${SCRIPT_DIR}/.env"
# load .env file if present
if [ -f "${ENV_FILE}" ]; then
  source "${ENV_FILE}"
  source "${SCRIPT_DIR}/.helper-functions.sh"
else
  echo "<${ENV_FILE}> is required, failing."
  exit 1
fi

# Ensure the necessary commands are present on machine
check_for_command_or_raise kubectl || exit 1
check_for_command_or_raise helm || exit 1
check_for_command_or_raise kind || exit 1
check_for_command_or_raise uv || exit 1

# Let's activate the venv
( [ ! -d "${VENV_DIR}" ] && uv venv "${VENV_DIR}" --python 3.11 ) || \
  source "${VENV_DIR}/bin/activate"

# Synchronize from the uv.lock
uv sync --extra dev

trap _cleanup EXIT

function _cleanup {
  # Cleanup temporary work directory
  rm -rf "${TEMP_DIR}"
  # Deactivate the venv
  source deactivate
}

DESCRIPTION="Configure the vault-secret-operator in targeted CLUSTER_NAME"

CLUSTER_NAME=$1
shift

if [ -z "${CLUSTER_NAME}" -o "${CLUSTER_NAME}" = "-h" -o "${CLUSTER_NAME}" = "--help" ]; then
  echo "Error: Targeted cluster name is mandatory."
  script_usage "${DESCRIPTION}"
  exit 1
fi

set_variables_for_cluster ${CLUSTER_NAME}
DEBUG_INSTRUCTIONS=

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      set -x
      export DEBUG_INSTRUCTIONS=1
      shift
      ;;
    -r|--recreate)
      cluster_recreate "${CLUSTER_NAME}"
      shift
      ;;
    -c|--create)
      cluster_create "${CLUSTER_NAME}"
      shift
      ;;
    -d|--delete)
      cluster_delete "${CLUSTER_NAME}"
      exit 0
      ;;
    -h|--help)
      script_usage "${DESCRIPTION}"
      shift
      ;;
    *)
      echo "Unknown option <$1>"
      script_usage "${DESCRIPTION}"
      exit 1
      ;;
  esac
done

create_shared_ca_files

execute_or_skip ${KUBECTL} create namespace "${NS_VSO}"
execute_or_skip ${KUBECTL} create namespace "${NS_APP}"

${HELM} repo add jetstack https://charts.jetstack.io
${HELM} repo add metallb https://metallb.github.io/metallb
${HELM} repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# ${HELM} repo add hashicorp https://helm.releases.hashicorp.com/
${HELM} repo update jetstack metallb ingress-nginx

install_or_skip cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true --set installCRDs=true
install_or_skip metallb metallb/metallb --namespace metallb
install_or_skip ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx

# Inject shared ca
execute_or_skip ${KUBECTL} delete secret shared-ca --namespace "${NS_VSO}"
${KUBECTL} create secret generic shared-ca --namespace "${NS_VSO}" \
           --from-file=ca.crt=$CA_CERT_FILECRT

# Let's wait for the ingress stack to be installed (required for argocd
# ingress to deploy)
${KUBECTL} wait pods --all --for=condition=Ready --timeout=60s \
   -n metallb

${KUBECTL} wait pods --all --for=condition=Ready --timeout=60s \
   -n ingress-nginx

${KUBECTL} apply -f - <<EOF
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: "local-metallb-pool-ingress"
  namespace: metallb
spec:
  addresses:
    - ${PRODUCTION_INGRESS_IP}/32
  serviceAllocation:
    namespaces:
    - ingress-nginx
    priority: 50
---
# Source: cluster-config/templates/metallb/ipaddresspools.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: "l2-advertisement-ingress"
  namespace: metallb
spec:
  ipAddressPools:
  - "local-metallb-pool-ingress"
EOF

# Create a cluster issuer shared-ca-issuer and generate a certificate for openbao
${KUBECTL} apply -f - <<EOF
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: shared-ca-issuer
spec:
  ca:
    secretName: shared-ca
EOF

${KUBECTL} apply -f - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kubeapi
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: HTTPS
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    cert-manager.io/cluster-issuer: "shared-ca-issuer"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - "${PRODUCTION_INGRESS_HOSTNAME}"
    secretName: production-ingress-tls
  rules:
  - host: "${PRODUCTION_INGRESS_HOSTNAME}"
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: kubernetes
            port:
              number: 443
EOF

CLUSTER_FQDN="https://kubernetes.default.svc"
if [ "${CLUSTER_NAME}" != "admin" ]; then
  KUBECFG_PRODFILE=$TEMP_DIR/local-cluster-production.yaml
  # Retrieve the kind configuration for that cluster
  kind get kubeconfig --name $CLUSTER_CONTEXT_PRODUCTION > ${KUBECFG_PRODFILE}
  # Then adapt to use the kubernetes ingress api instead of the host related
  # access (which is not possible from the "admin" cluster)
  URL_TO_REPLACE=$(awk '/server: /{print $2}' ${KUBECFG_PRODFILE})
  CLUSTER_FQDN="https://${PRODUCTION_INGRESS_HOSTNAME}"
  sed -i "s#${URL_TO_REPLACE}#${CLUSTER_FQDN}#gi" ${KUBECFG_PRODFILE}

  CLUSTER_REFNAME="kind-local-cluster-production"
  SECRET_REFNAME="${CLUSTER_REFNAME}-secret"

  execute_or_skip $KUBECTL_ADMIN delete secret -n ${NS_ARGOCD} \
    ${SECRET_REFNAME}

  # Call argocd cluster add even though it's not fully finishing with success. It's a
  # workaround specific to the local cluster and won't be used that way in production
  # any ways. This cli call will create a service account, cluster role and cluster role
  # binding in the argocd-manager namespace with the sufficient privileges
  argocd cluster add "${CLUSTER_REFNAME}" -y || \
    echo "argocd cluster add failed, but ServiceAccount, ClusterRole and ClusterRoleBinding should exist now."

  TOKEN_ACCESS=$($KUBECTL_PRODUCTION create token argocd-manager -n kube-system)

  for ns in ${NS_ARGOCD} ${NS_OPENBAO}; do
    ${KUBECTL_ADMIN} apply --namespace $ns -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_REFNAME}
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: ${CLUSTER_REFNAME}
  server: ${CLUSTER_FQDN}
  config: |
    {
      "bearerToken": "${TOKEN_ACCESS}",
      "tlsClientConfig": {
        "insecure": true
      }
    }
EOF
    done
fi

VSO_VERSION=1.1.0
# Now that argocd is configured properly to deal with the other cluster, let's
# install vso with argocd!
$KUBECTL_ADMIN apply -f - <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: local-cluster-vso
  namespace: ${NS_ARGOCD}
spec:
  project: default
  source:
    repoURL: https://helm.releases.hashicorp.com/
    chart: vault-secrets-operator
    targetRevision: v${VSO_VERSION}
    helm:
      releaseName: vso
      values: |
        controller:
          manager:
            logging:
              level: trace
          hostAliases:
            - ip: ${ADMIN_INGRESS_IP}
              hostnames:
              - ${ADMIN_INGRESS_HOSTNAME}
            - ip: ${PRODUCTION_INGRESS_IP}
              hostnames:
              - ${PRODUCTION_INGRESS_HOSTNAME}
        defaultVaultConnection:
          enabled: true
          address: ${OPENBAO_ENDPOINT}
          caCertSecret: shared-ca
  destination:
    server: ${CLUSTER_FQDN}
    namespace: ${NS_VSO}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF


# Wait for argocd sync window to kick in
${KUBECTL} wait deployment -n "${NS_VSO}" --all --for=condition=Available \
  --timeout=60s || \
  ( echo "Waiting with argocd ns failed... " && \
    echo "Let's fallback to sleep to give some time for argocd sync window to kick in." \
    && sleep 5 )

${KUBECTL} wait deployment -n "${NS_VSO}" --all --for=condition=Available \
  --timeout=60s

echo "Start configuring BAO resources in cluster <${CLUSTER_REFNAME}>..."

# See documentation and examples here:
# https://developer.hashicorp.com/vault/api-docs/system/mounts
# https://support.hashicorp.com/hc/en-us/articles/4412233931667-Translate-Vault-CLI-commands-to-HTTP-API
# https://gist.github.com/exAspArk/e210523a4bcb988cdfb24a114d46ddf0

${KUBECTL_ADMIN} wait pod openbao-0 --for=condition=Ready --timeout=60s -n "${NS_OPENBAO}"

# Installs a cronjob which triggers the approle configuration in openbao for the
# targeted cluster.

${KUBECTL_ADMIN} apply --namespace ${NS_OPENBAO} -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: bao-script-utils
data:
  init_bao_cluster.py: |
    #!/usr/bin/env python3

    # Script in charge to manage the bao cluster initialization
    # - enable kv-v2 secret
    # - enable approle authentication
    # - write policy access (for an approle)
    # - create said approle

    # See documentation and examples here:
    # https://developer.hashicorp.com/vault/api-docs/system/mounts
    # https://support.hashicorp.com/hc/en-us/articles/4412233931667-Translate-Vault-CLI-commands-to-HTTP-API
    # https://gist.github.com/exAspArk/e210523a4bcb988cdfb24a114d46ddf0

    import click
    import hvac
    from typing import Optional


    def get_client(url: str, token: Optional[str] = None) -> hvac.Client:
        """Client HVAC Initialization"""
        # TODO: Turn off the verify to True (for tls authentication)
        client = hvac.Client(url=url, token=token, verify=False)
        if not client.is_authenticated():
            raise ValueError("Impossible to authenticate with Vault/OpenBao.")
        return client


    @click.group()
    @click.option('--url', required=True, help="Vault/OpenBao URL")
    @click.option('--token', required=True, help="Vault/OpenBao Access Token")
    @click.pass_context
    def cli(ctx, url, token):
        """Mount initialization"""

        ctx.ensure_object(dict)
        ctx.obj['client'] = get_client(url, token)


    @cli.command()
    @click.argument('path')
    @click.argument('backend_type', default='kv')
    @click.pass_context
    def enable_secrets_engine(ctx, path, backend_type):
        """Vault/OpenBao initialization"""
        client = ctx.obj['client']

        # FIXME: Improve creation without try/except pattern
        try:
            client.sys.enable_secrets_engine(
                backend_type=backend_type,
                path=path,
                options={'version': '2'}
            )
            msg = f"Mount '{path}' with type '{backend_type}' created."
            click.echo()
        except:
            msg = f"Mount '{path}' with type '{backend_type}' already exists."
        finally:
            click.echo(msg)


    def read_app_role(client, role_name, mount):
        """Retrieve app role"""
        return client.auth.approle.read_role_id(role_name, mount_point=mount)


    @cli.command()
    @click.argument('policy_name')
    @click.argument('policy_rule_filename', type=click.Path(exists=True))
    @click.pass_context
    def create_policy(ctx, policy_name, policy_rule_filename):
        """Create policy in Vault/OpenBao."""
        client = ctx.obj['client']
        with open(policy_rule_filename, 'r') as f:
            rules = ''.join(f.readlines())

        try:
            client.sys.read_policy(policy_name)
            msg = f"Policy '{policy_name}' already exists."
        except:
            client.sys.create_or_update_policy(
                name=policy_name,
                policy=rules
            )
            msg = f"Policy '{policy_name}' created."
        click.echo(msg)


    @cli.command()
    @click.argument('role_name')
    @click.option('--mount', required=True, help="AppRole mount path")
    @click.option('--policy-name', required=True, help="Policy for that appRole")
    @click.pass_context
    def create_approle(ctx, role_name, mount, policy_name):
        """Create AppRole in Vault/OpenBao."""
        client = ctx.obj['client']
        # Enable approle authentication
        try:
            client.sys.enable_auth_method(
                method_type='approle',
                path=mount
            )
        except:
            # Already enabled, so we skip that step
            pass

        app_role = client.auth.approle
        try:
            app_role.read_role(role_name, mount_point=mount)
            msg = f"AppRole '{role_name}' already exists."
        except:
            app_role.create_or_update_approle(
                role_name=role_name,
                mount_point=mount,
                token_policies=[policy_name],
            )
            role_id = get_role_id(client, role_name, mount)
            msg = f"AppRole '{role_name}' created with {role_id}"
        click.echo(msg)


    def get_role_id(client, role_name, mount):
        """Retrieve the role id from the role name mounted in the path mount."""
        app_role_d = client.auth.approle.read_role_id(role_name, mount_point=mount)
        return app_role_d['data']['role_id']


    def generate_secret_id(client, role_name, mount):
        """Generate a secret id from the role name mounted in the path mount."""
        secret_id_d = client.auth.approle.generate_secret_id(role_name, mount_point=mount)
        return secret_id_d['data']['secret_id']


    @cli.command()
    @click.argument('role_name')
    @click.option('--mount', required=True, help="AppRole mount path")
    @click.pass_context
    def get_approle_id(ctx, role_name, mount):
        """Retrieve the role id from the role_name."""
        client = ctx.obj['client']
        role_id = get_role_id(client, role_name, mount)
        click.echo(role_id)


    @cli.command()
    @click.argument('role_name')
    @click.option('--mount', required=True, help="AppRole mount path")
    @click.pass_context
    def create_approle_secret_id(ctx, role_name, mount):
        """Create an approle's secret id from the role_name."""
        client = ctx.obj['client']
        secret_id = generate_secret_id(client, role_name, mount)
        click.echo(secret_id)


    @cli.command()
    @click.option('--role-name', required=True, help="AppRole name")
    @click.option('--mount', required=True, help="AppRole mount path")
    @click.option('--targeted-cluster-url', required=True,
                  help="Ingress targeted cluster url")
    @click.option('--secret-name', required=True,
                  help="Name of the secret in the target cluster")
    @click.option('--secret-namespace', required=True,
                  help="Namespace of the secret in the targeted cluster")
    @click.pass_context
    def create_secret_in_targeted_cluster(
        ctx, role_name, mount, targeted_cluster_url, secret_name, secret_namespace
    ):
        """Create the secret with approle id/secret-id in the targeted cluster'."""
        hvac_client = ctx.obj['client']
        secret_id = generate_secret_id(hvac_client, role_name, mount)

        from kubernetes import client, config
        from kubernetes.client.configuration import Configuration
        from json import loads
        from base64 import b64encode

        # Initialize connection to targeted kubernetes cluster
        client_config = Configuration()
        # For local clusters, no need
        client_config.verify_ssl = False

        # FIXME: Make it a bit more parametric?
        # Configuration file holding the bearer token
        with open("/opt/swh/.kube/config", "r") as f: data = loads(f.read())
        client_config.api_key['authorization'] = data['bearerToken']
        client_config.api_key_prefix['authorization'] = 'Bearer'
        client_config.host = targeted_cluster_url

        # Create the approle secret structure (a simple key/value: id/secret-id)
        secret = client.V1Secret()
        secret.metadata = client.V1ObjectMeta(name=secret_name)
        secret.type = "Opaque"
        secret.data = {"id": b64encode(secret_id.encode()).decode()}

        # Actually create the secret in the targeted cluster
        api_instance = client.CoreV1Api(api_client=client.ApiClient(configuration=client_config))
        api_instance.create_namespaced_secret(namespace=secret_namespace, body=secret)

    if __name__ == '__main__':
        cli()

  init-bao-cluster.sh: |
    #!/bin/bash

    set -x

    [ -z "\${OPENBAO_ENDPOINT}" ] && \
      echo "<OPENBAO_ENDPOINT> env variable must be set" && exit 1
    [ -z "\${OPENBAO_DEFAULT_TOKEN}" ] && \
      echo "<OPENBAO_DEFAULT_TOKEN> env variable must be set" && exit 1
    [ -z "\${POLICY_NAME}" ] && \
      echo "<POLICY_NAME> env variable must be set" && exit 1
    [ -z "\${MOUNT}" ] && \
      echo "<MOUNT> env variable must be set" && exit 1
    [ -z "\${ROLE}" ] && \
      echo "<ROLE> env variable must be set" && exit 1
    [ -z "\${BAO_SCRIPT}" ] && \
      echo "<BAO_SCRIPT> env variable must be set" && exit 1
    [ -z "\${CLUSTER_TARGET_URL}" ] && \
      echo "<CLUSTER_TARGET_URL> env variable must be set" && exit 1
    [ -z "\${CLUSTER_TARGET_SECRET_NAME}" ] && \
      echo "<CLUSTER_TARGET_SECRET_NAME> env variable must be set" && exit 1
    [ -z "\${CLUSTER_TARGET_SECRET_NAMESPACE}" ] && \
      echo "<CLUSTER_TARGET_SECRET_NAMESPACE> env variable must be set" && exit 1

    TEMP_DIR=\$(mktemp -d)

    uv pip install hvac click kubernetes

    \${BAO_SCRIPT} --url \${OPENBAO_ENDPOINT} \
      --token \${OPENBAO_DEFAULT_TOKEN} \
      enable-secrets-engine \${MOUNT} 2>/dev/null

    # Then we create the policy for the future approle to create
    POLICY_FILENAME="\${POLICY_NAME}.hcl"
    POLICY_FILE="\${TEMP_DIR}/\${POLICY_FILENAME}"
    cat > "\${POLICY_FILE}" << EOF
      path "\${MOUNT}/data/*" {
      capabilities = ["list", "read"]
    }

    path "\${MOUNT}/metadata/*" {
      capabilities = ["list", "read"]
    }
    EOF

    \${BAO_SCRIPT} --url \${OPENBAO_ENDPOINT} \
      --token \${OPENBAO_DEFAULT_TOKEN} \
      create-policy \${POLICY_NAME} \${POLICY_FILE} 2>/dev/null

    # Finally we attach that policy to the new AppRole we create
    \${BAO_SCRIPT} --url \${OPENBAO_ENDPOINT} \
      --token \${OPENBAO_DEFAULT_TOKEN} \
      create-approle \
      --mount \${MOUNT} \
      --policy-name \${POLICY_NAME} \
      \${ROLE} 2>/dev/null

    \${BAO_SCRIPT} --url \${OPENBAO_ENDPOINT} \
      --token \${OPENBAO_DEFAULT_TOKEN} \
      create-secret-in-targeted-cluster \
      --role-name \${ROLE} \
      --mount \${MOUNT} \
      --targeted-cluster-url \${CLUSTER_TARGET_URL} \
      --secret-name \${CLUSTER_TARGET_SECRET_NAME} \
      --secret-namespace \${CLUSTER_TARGET_SECRET_NAMESPACE} \
      2>/dev/null

---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: init-bao-cluster
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: "Forbid"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: init-bao-cluster
              # FIXME: Use a dedicated docker image for this bao configuration
              image: container-registry.softwareheritage.org/swh/infra/swh-apps/toolbox:20260206.3
              command:
              - /script/init-bao-cluster.sh
              env:
                - name: OPENBAO_ENDPOINT
                  value: ${OPENBAO_ENDPOINT}
                - name: OPENBAO_DEFAULT_TOKEN
                  value: ${OPENBAO_DEFAULT_TOKEN}
                - name: ROLE
                  value: ${ROLE}
                - name: MOUNT
                  value: ${MOUNT}
                - name: POLICY_NAME
                  value: ${POLICY_NAME}
                - name: BAO_SCRIPT
                  value: /script/init_bao_cluster.py
                - name: CLUSTER_TARGET_URL
                  value: ${CLUSTER_FQDN}
                - name: CLUSTER_TARGET_SECRET_NAME
                  value: ${VAULT_AUTH_NAME}
                - name: CLUSTER_TARGET_SECRET_NAMESPACE
                  value: ${NS_APP}
              imagePullPolicy: IfNotPresent
              volumeMounts:
              - name: bao-script-utils
                mountPath: /script
              - name: kubeconfig
                mountPath: "/opt/swh/.kube/config"
                subPath: config
                readOnly: true

          volumes:
          - name: bao-script-utils
            configMap:
              name: bao-script-utils
              defaultMode: 0555
          - name: kubeconfig
            secret:
              secretName: ${SECRET_REFNAME}
          restartPolicy: OnFailure

EOF

$KUBECTL_ADMIN create job --from=cronjob/init-bao-cluster --namespace ${NS_OPENBAO} \
  manual-init-bao-cluster-job

# Wait for the secret created by the cronjob executed in the admin cluster
echo "# Waiting for the secret ${ROLE_SECRET_NAME} -in namespace ${NS_APP}"
timeout 20s bash -c "until $KUBECTL get secret ${ROLE_SECRET_NAME} -n ${NS_APP} &>/dev/null; do printf \".\"; sleep 0.2; done"

ROLE_ID=$(./init_bao_cluster.py --url ${OPENBAO_ENDPOINT} \
  --token ${OPENBAO_DEFAULT_TOKEN} \
  get-approle-id ${ROLE} \
  --mount ${MOUNT} \
  2>/dev/null)

# Finally configure VaultAuth to allow vso to synchronize kubernetes secret from bao
${KUBECTL} apply -f - << EOF
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${VAULT_AUTH_NAME}
  namespace: ${NS_APP}
spec:
  method: appRole
  mount: ${MOUNT}
  appRole:
    roleId: ${ROLE_ID}
    secretRef: ${ROLE_SECRET_NAME}
  allowedNamespaces:
    - "*"
EOF
