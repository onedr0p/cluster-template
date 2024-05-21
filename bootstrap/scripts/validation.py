from functools import wraps
from shutil import which
from typing import Callable, cast
from zoneinfo import available_timezones
import netaddr
import re
import socket
import sys

GLOBAL_CLI_TOOLS = ["age", "flux", "helmfile", "sops", "jq", "kubeconform", "kustomize", "talosctl", "talhelper"]
CLOUDFLARE_TOOLS = ["cloudflared"]


def required(*keys: str):
    def wrapper_outter(func: Callable):
        @wraps(func)
        def wrapper(data: dict, *_, **kwargs) -> None:
            for key in keys:
                if data.get(key) is None:
                    raise ValueError(f"Missing required key {key}")
            return func(*[data[key] for key in keys], **kwargs)

        return wrapper

    return wrapper_outter


def validate_python_version() -> None:
    required_version = (3, 11, 0)
    if sys.version_info < required_version:
        raise ValueError(f"Python {sys.version_info} is below 3.11. Please upgrade.")


def validate_ip(ip: str) -> str:
    try:
        netaddr.IPAddress(ip)
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid IP address {ip}") from e
    return ip


def validate_network(cidr: str, family: int) -> str:
    try:
        network = netaddr.IPNetwork(cidr)
        if network.version != family:
            raise ValueError(f"Invalid CIDR family {network.version}")
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid CIDR {cidr}") from e
    return cidr


def validate_node(node: dict, node_cidr: str) -> None:
    if not node.get("name"):
        raise ValueError(f"A node is missing a name")
    if not re.match(r"^[a-z0-9-]+$", node.get('name')):
        raise ValueError(f"Node {node.get('name')} has an invalid name")
    if not node.get("disk"):
        raise ValueError(f"Node {node.get('name')} is missing disk")
    if not node.get("mac_addr"):
        raise ValueError(f"Node {node.get('name')} is missing mac_addr")
    if not re.match(r"(?:[0-9a-fA-F]:?){12}", node.get("mac_addr")):
        raise ValueError(f"Node {node.get('name')} has an invalid mac_addr, is this a MAC address?")
    if node.get("address"):
        ip = validate_ip(node.get("address"))
        if netaddr.IPAddress(ip, 4) not in netaddr.IPNetwork(node_cidr):
            raise ValueError(f"Node {node.get('name')} is not in the node CIDR {node_cidr}")
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(5)
            result = sock.connect_ex((ip, 50000))
            if result != 0:
                raise ValueError(f"Node {node.get('name')} port 50000 is not open")


@required("bootstrap_cloudflare")
def validate_cli_tools(cloudflare: dict, **_) -> None:
    for tool in GLOBAL_CLI_TOOLS:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")
    for tool in CLOUDFLARE_TOOLS if cloudflare.get("enabled", False) else []:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")


@required("bootstrap_sops_age_pubkey")
def validate_age(key: str, **_) -> None:
    if not re.match(r"^age1[a-z0-9]{0,58}$", key):
        raise ValueError(f"Invalid Age public key {key}")


@required("bootstrap_node_network", "bootstrap_node_inventory")
def validate_nodes(node_cidr: str, nodes: dict[list], **_) -> None:
    node_cidr = validate_network(node_cidr, 4)

    controllers = [node for node in nodes if node.get('controller') == True]
    if len(controllers) < 1:
        raise ValueError(f"Must have at least one controller node")
    if len(controllers) % 2 == 0:
        raise ValueError(f"Must have an odd number of controller nodes")
    for node in controllers:
        validate_node(node, node_cidr)

    workers = [node for node in nodes if node.get('controller') == False]
    for node in workers:
        validate_node(node, node_cidr)


def validate(data: dict) -> None:
    validate_python_version()
    validate_cli_tools(data)
    validate_age(data)

    if not data.get("skip_tests", False):
        validate_nodes(data)
