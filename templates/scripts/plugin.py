from pathlib import Path
from typing import Any
from netaddr import IPNetwork

import makejinja
import re
import json


# Return the filename of a path without the j2 extension
def basename(value: str) -> str:
    return Path(value).stem


# Return the nth host in a CIDR range
def nthhost(value: str, query: int) -> str:
    value = IPNetwork(value)
    try:
        nth = int(query)
        if value.size > nth:
            return str(value[nth])
    except ValueError:
        return False
    return value


# Return the age public key from age.key
def age_public_key() -> str:
    try:
        with open('age.key', 'r') as file:
            file_content = file.read().strip()
    except FileNotFoundError as e:
        raise FileNotFoundError(f"File not found: age.key") from e
    key_match = re.search(r"# public key: (age1[\w]+)", file_content)
    if not key_match:
        raise ValueError("Could not find public key in age.key")
    return key_match.group(1)


# Return the age private key from age.key
def age_private_key() -> str:
    try:
        with open('age.key', 'r') as file:
            file_content = file.read().strip()
    except FileNotFoundError as e:
        raise FileNotFoundError(f"File not found: age.key") from e
    key_match = re.search(r"(AGE-SECRET-KEY-[\w]+)", file_content)
    if not key_match:
        raise ValueError("Could not find private key in age.key")
    return key_match.group(1)


# Return cloudflare tunnel fields from cloudflare-tunnel.json
def cloudflare_tunnel(value: str) -> str:
    try:
        with open('cloudflare-tunnel.json', 'r') as file:
            try:
                return json.load(file).get(value)
            except json.JSONDecodeError as e:
                raise ValueError(f"Could not decode cloudflare-tunnel.json file") from e
    except FileNotFoundError as e:
        raise FileNotFoundError(f"File not found: cloudflare-tunnel.json") from e


# Return the GitHub deploy key from github-deploy.key
def github_deploy_key() -> str:
    try:
        with open('github-deploy.key', 'r') as file:
            file_content = file.read().strip()
    except FileNotFoundError as e:
        raise FileNotFoundError(f"File not found: github-deploy.key") from e
    return file_content


# Return the Flux / GitHub push token from github-push-token.txt
def github_push_token() -> str:
    try:
        with open('github-push-token.txt', 'r') as file:
            file_content = file.read().strip()
    except FileNotFoundError as e:
        raise FileNotFoundError(f"File not found: github-push-token.txt") from e
    return file_content


# Return a list of files in the talos patches directory
def talos_patches(value: str) -> list[str]:
    path = Path(f'templates/config/talos/patches/{value}')
    if not path.is_dir():
        return []
    return [str(f) for f in sorted(path.glob('*.yaml.j2')) if f.is_file()]


class Plugin(makejinja.plugin.Plugin):
    def __init__(self, data: dict[str, Any]):
        self._data = data


    def data(self) -> makejinja.plugin.Data:
        data = self._data

        # Set default values for optional fields
        data.setdefault('node_default_gateway', nthhost(data.get('node_cidr'), 1))
        data.setdefault('node_dns_servers', ['1.1.1.1', '1.0.0.1'])
        data.setdefault('node_ntp_servers', ['162.159.200.1', '162.159.200.123'])
        data.setdefault('cluster_pod_cidr', '10.42.0.0/16')
        data.setdefault('cluster_svc_cidr', '10.43.0.0/16')
        data.setdefault('repository_branch', 'main')
        data.setdefault('repository_visibility', 'public')
        data.setdefault('cloudflare_cluster_issuer', 'staging')
        data.setdefault('cilium_loadbalancer_mode', 'dsr')

        # If all BGP keys are set, enable BGP
        bgp_keys = ['cilium_bgp_router_addr', 'cilium_bgp_router_asn', 'cilium_bgp_node_asn']
        bgp_enabled = all(data.get(key) for key in bgp_keys)
        data.setdefault('cilium_bgp_enabled', bgp_enabled)

        return data


    def filters(self) -> makejinja.plugin.Filters:
        return [
            basename,
            nthhost
        ]


    def functions(self) -> makejinja.plugin.Functions:
        return [
            age_private_key,
            age_public_key,
            cloudflare_tunnel,
            github_deploy_key,
            github_push_token,
            talos_patches
        ]
