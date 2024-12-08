from functools import wraps
from typing import Callable
import dns.resolver
import netaddr
import ntplib
import re
import socket
import sys

RESERVED_NODE_NAMES = ["global", "controller", "worker"]

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
        raise ValueError(f"Invalid Python version {sys.version_info}, must be 3.11 or higher")


def validate_node(node: dict, node_cidr: str) -> None:
    if not node.get('name') or not re.match(r"^[a-z0-9-]+$", node.get('name')):
        raise ValueError(f"Invalid node name {node.get('name')} for {node.get('name')}, must be not empty and match [a-z0-9-]")
    if node.get('name') in RESERVED_NODE_NAMES:
        raise ValueError(f"Invalid node name {node.get('name')} for {node.get('name')}, must not be any of {', '.join(RESERVED_NODE_NAMES)}")
    if not node.get('disk'):
        raise ValueError(f"Invalid node disk {node.get('disk')} for {node.get('name')}, must be not empty")
    if not node.get('mac_addr') or not re.match(r"(?:[0-9a-fA-F]:?){12}", node.get('mac_addr')):
        raise ValueError(f"Invalid node mac_addr {node.get('mac_addr')} for {node.get('name')}, must be not empty and match [0-9a-fA-F]:?")
    if node.get('schematic_id'):
        if not re.match(r"^[a-z0-9]{64}$", node.get('schematic_id')):
            raise ValueError(f"Invalid node schematic_id {node.get('schematic_id')} for {node.get('name')}, must match [a-z0-9]{64}")

    try:
        netaddr.IPAddress(node.get('address'))
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid IP address {node.get('address')}") from e

    if netaddr.IPAddress(node.get('address'), 4) not in netaddr.IPNetwork(node_cidr):
        raise ValueError(
            f"Invalid node address {node.get('address')} for {node.get('name')}, must be in CIDR {node_cidr}"
        )

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(5)
        result = sock.connect_ex((node.get('address'), 50000))
        if result != 0:
            raise ValueError(
                f"Unable to connect to node {node.get('name')}, port 50000 is not connectable"
            )


@required("bootstrap_cluster_name")
def validate_cluster_name(name: str = "home-kubernetes", **_) -> None:
    if not re.match(r"^[a-z0-9-]+$", name):
        raise ValueError(f"Invalid bootstrap_cluster_name {name}, must be not empty and match [a-z0-9-]+")


@required("bootstrap_schematic_id")
def validate_schematic_id(id: str, **_) -> None:
    if not re.match(r"^[a-z0-9]{64}$", id):
        raise ValueError(f"Invalid bootstrap_schematic_id {id}, must be not empty and match [a-z0-9]{64}")


@required("bootstrap_node_network", "bootstrap_node_inventory")
def validate_nodes(node_cidr: str, nodes: dict[list], **_) -> None:
    try:
        network = netaddr.IPNetwork(node_cidr)
        if network.version != 4:
            raise ValueError(f"Invalid bootstrap_node_network {network.version}, must be IPv4")
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid bootstrap_node_network {node_cidr}") from e

    controllers = [node for node in nodes if node.get('controller') == True]
    if len(controllers) < 1 or len(controllers) % 2 == 0:
        raise ValueError(f"Invalid number of controllers {len(controllers)}, must be odd and at least 1")
    for node in controllers:
        validate_node(node, node_cidr)

    workers = [node for node in nodes if node.get('controller') == False]
    for node in workers:
        validate_node(node, node_cidr)


@required("bootstrap_dns_servers")
def validate_dns_servers(servers: list = ["1.1.1.1","1.0.0.1"], **_) -> None:
    resolver = dns.resolver.Resolver()
    resolver.nameservers = servers
    resolver.timeout = 5
    resolver.lifetime = 5

    try:
        resolver.resolve("cloudflare.com")
    except Exception as e:
        raise ValueError(f"Unable to resolve cloudflare.com with DNS servers {servers}") from e


@required("bootstrap_ntp_servers")
def validate_ntp_servers(servers: list = ["162.159.200.1","162.159.200.123"], **_) -> None:
    client = ntplib.NTPClient()
    for server in servers:
        try:
            client.request(server, version=3)
        except Exception as e:
            raise ValueError(f"Unable to connect to NTP server {server}") from e


@required("bootstrap_age_pubkey")
def validate_age(key: str, **_) -> None:
    if not re.match(r"^age1[a-z0-9]{0,58}$", key):
        raise ValueError(f"Invalid bootstrap_age_pubkey {key}, must be not empty and match age1[a-z0-9]{0,58}")


def validate(data: dict) -> None:
    validate_python_version()
    validate_cluster_name(data)
    validate_schematic_id(data)
    validate_age(data)

    if not data.get('skip_tests', False):
        validate_nodes(data)

    validate_dns_servers(data)
    validate_ntp_servers(data)
