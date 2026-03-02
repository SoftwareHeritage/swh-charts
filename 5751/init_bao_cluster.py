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
@click.option('--kubeconfig', 'kubeconfig_path', type=click.Path(exists=True))
@click.pass_context
def create_secret_in_targeted_cluster(
    ctx, role_name, mount, targeted_cluster_url, secret_name, secret_namespace,
    kubeconfig_path
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

        # Configuration file holding the bearer token
    with open(kubeconfig_path, "r") as f: data = loads(f.read())
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
    try:
        # We try to delete the actual secret so we can create anew
        api_instance.delete_namespaced_secret(secret_name, secret_namespace)
    except:
        pass
    finally:
        # It does not exist, we create it
        api_instance.create_namespaced_secret(namespace=secret_namespace, body=secret)


if __name__ == '__main__':
    cli()
