from pathlib import Path
from typing import Any

import base64
import ipaddress
import makejinja
import re
import json


# Return the filename of a path without the j2 extension
def basename(value: str) -> str:
    return Path(value).stem


# Return the nth host in a CIDR range
def nthhost(value: str, query: int) -> str:
    try:
        network = ipaddress.ip_network(value, strict=False)
        if 0 <= query < network.num_addresses:
            return str(network[query])
    except ValueError:
        pass
    return False


# Return the age public or private key from age.key
def age_key(key_type: str, file_path: str = 'age.key') -> str:
    try:
        with open(file_path, 'r') as file:
            file_content = file.read().strip()
        if key_type == 'public':
            key_match = re.search(r"# public key: (age1[\w]+)", file_content)
            if not key_match:
                raise ValueError("Could not find public key in the age key file.")
            return key_match.group(1)
        elif key_type == 'private':
            key_match = re.search(r"(AGE-SECRET-KEY-[\w]+)", file_content)
            if not key_match:
                raise ValueError("Could not find private key in the age key file.")
            return key_match.group(1)
        else:
            raise ValueError("Invalid key type. Use 'public' or 'private'.")
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return cloudflare tunnel fields from cloudflare-tunnel.json
def cloudflare_tunnel_id(file_path: str = 'cloudflare-tunnel.json') -> str:
    try:
        with open(file_path, 'r') as file:
            data = json.load(file)
        tunnel_id = data.get("TunnelID")
        if tunnel_id is None:
            raise KeyError(f"Missing 'TunnelID' key in {file_path}")
        return tunnel_id

    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except json.JSONDecodeError:
        raise ValueError(f"Could not decode JSON file: {file_path}")
    except KeyError as e:
        raise KeyError(f"Error in JSON structure: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return cloudflare tunnel fields from cloudflare-tunnel.json in TUNNEL_TOKEN format
def cloudflare_tunnel_secret(file_path: str = 'cloudflare-tunnel.json') -> str:
    try:
        with open(file_path, 'r') as file:
            data = json.load(file)
        transformed_data = {
            "a": data["AccountTag"],
            "t": data["TunnelID"],
            "s": data["TunnelSecret"]
        }
        json_string = json.dumps(transformed_data, separators=(',', ':'))
        return base64.b64encode(json_string.encode('utf-8')).decode('utf-8')

    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except json.JSONDecodeError:
        raise ValueError(f"Could not decode JSON file: {file_path}")
    except KeyError as e:
        raise KeyError(f"Missing key in JSON file {file_path}: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while processing {file_path}: {e}")


# Return the GitHub deploy key from github-deploy.key
def github_deploy_key(file_path: str = 'github-deploy.key') -> str:
    try:
        with open(file_path, 'r') as file:
            return file.read().strip()
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while reading {file_path}: {e}")


# Return the Flux / GitHub push token from github-push-token.txt
def github_push_token(file_path: str = 'github-push-token.txt') -> str:
    try:
        with open(file_path, 'r') as file:
            return file.read().strip()
    except FileNotFoundError:
        raise FileNotFoundError(f"File not found: {file_path}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error while reading {file_path}: {e}")


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
        data.setdefault('cilium_loadbalancer_mode', 'dsr')

        # If all BGP keys are set, enable BGP
        bgp_keys = ['cilium_bgp_router_addr', 'cilium_bgp_router_asn', 'cilium_bgp_node_asn']
        bgp_enabled = all(data.get(key) for key in bgp_keys)
        data.setdefault('cilium_bgp_enabled', bgp_enabled)

        # If there is more than one node, enable spegel
        spegel_enabled = len(data.get('nodes')) > 1
        data.setdefault('spegel_enabled', spegel_enabled)

        return data


    def filters(self) -> makejinja.plugin.Filters:
        return [
            basename,
            nthhost
        ]


    def functions(self) -> makejinja.plugin.Functions:
        return [
            age_key,
            cloudflare_tunnel_id,
            cloudflare_tunnel_secret,
            github_deploy_key,
            github_push_token,
            talos_patches
        ]
