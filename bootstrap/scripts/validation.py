from email_validator import validate_email, EmailNotValidError, EmailUndeliverableError
from functools import wraps
from shutil import which
from typing import Callable, Optional
from zoneinfo import available_timezones
import CloudFlare
import json
import netaddr
import re
import requests
import socket
import sys

DISTRIBUTIONS = ["k0s", "k3s", "talos"]
GLOBAL_CLI_TOOLS = ["age", "cloudflared", "flux", "sops", "jq", "kubeconform", "kustomize"]
TALOS_CLI_TOOLS = ["talosctl", "talhelper"]
K0S_CLI_TOOLS = ["k0sctl"]


def required(*keys: str):
    def wrapper_outter(func: Callable):
        @wraps(func)
        def wrapper(data: dict, *args, **kwargs) -> None:
            for key in keys:
                if data.get(key) is None:
                    raise ValueError(f"Missing required key {key}")
            return func(*[data[key] for key in keys], **kwargs)

        return wrapper

    return wrapper_outter


def _validate_ip(ip: str) -> str:
    try:
        netaddr.IPAddress(ip)
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid IP address {ip}") from e
    return ip


def _validate_cidr(cidr: str, family: int) -> str:
    try:
        network = netaddr.IPNetwork(cidr)
        if network.version != family:
            raise ValueError(f"Invalid CIDR family {network.version}")
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid CIDR {cidr}") from e
    return cidr


def _validate_distribution(distribution: str) -> None:
    if distribution not in DISTRIBUTIONS:
        raise ValueError(f"Invalid distribution {distribution}")
    return distribution


def _validate_node(node: dict, node_cidr: str, distribution: str) -> None:
    if not node.get("name"):
        raise ValueError(f"A node is missing a name")
    if not node.get("username") and distribution not in ["k0s", "k3s"]:
        raise ValueError(f"Node {node.get('name')} is missing a username")
    if not node.get("diskSerial") and distribution in ["talos"]:
        raise ValueError(f"Node {node.get('name')} is missing a disk serial")
    if not re.match(r"^[a-z0-9-\.]+$", node.get('name')):
        raise ValueError(f"Node {node.get('name')} has an invalid name")
    ip = _validate_ip(node.get("address"))
    if netaddr.IPAddress(ip, 4) not in netaddr.IPNetwork(node_cidr):
        raise ValueError(f"Node {node.get('name')} is not in the node CIDR {node_cidr}")
    port = 50000 if distribution == "talos" else 22
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(5)
        result = sock.connect_ex((ip, port))
        if result != 0:
            raise ValueError(f"Node {node.get('name')} port {port} is not open")


def validate_python_version() -> None:
    required_version = (3, 11, 0)
    if sys.version_info < required_version:
        raise ValueError(f"Python version is below 3.11. Please upgrade.")


@required("bootstrap_distribution")
def validate_cli_tools(distribution: str, **_) -> None:
    distro = _validate_distribution(distribution)
    for tool in GLOBAL_CLI_TOOLS:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")
    for tool in TALOS_CLI_TOOLS if distro == "talos" else []:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")
    for tool in K0S_CLI_TOOLS if distro == "k0s" else []:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")


@required("bootstrap_distribution")
def validate_distribution(distribution: str, **_) -> None:
    _validate_distribution(distribution)


@required("bootstrap_github_username", "bootstrap_github_repository_name", "bootstrap_advanced_flags")
def validate_github(username: str, repository: str, advanced_flags: dict, **_) -> None:
    try:
        request = requests.get(
            f"https://api.github.com/repos/{username}/{repository}/branches/{advanced_flags.get('github_repository_branch', 'main')}")
        if request.status_code != 200:
            raise ValueError(
                f"GitHub repository {username}/{repository} branch {advanced_flags.get('github_repository_branch', 'main')} not found")
    except requests.exceptions.RequestException as e:
        raise ValueError(
            f"GitHub repository {username}/{repository} branch {advanced_flags.get('github_repository_branch', 'main')} not found") from e


@required("bootstrap_age_public_key")
def validate_age(key: str, **_) -> None:
    if not re.match(r"^age1[a-z0-9]{0,58}$", key):
        raise ValueError(f"Invalid Age public key {key}")


@required("bootstrap_timezone")
def validate_timezone(timezone: str, **_) -> None:
    if timezone not in available_timezones():
        raise ValueError(f"Invalid timezone {timezone}")


@required("bootstrap_ipv6_enabled", "bootstrap_cluster_cidr", "bootstrap_service_cidr")
def validate_cluster_cidrs(ipv6_enabled: bool, cluster_cidr: str, service_cidr: str, **_) -> None:
    if not isinstance(ipv6_enabled, bool):
        raise ValueError(f"Invalid IPv6 enabled {ipv6_enabled}")

    if cluster_cidr == service_cidr:
        raise ValueError(f"Cluster CIDR {cluster_cidr} is the same as service CIDR {service_cidr}")

    if ipv6_enabled:
        if len(cluster_cidr.split(",")) != 2:
            raise ValueError(f"Invalid cluster CIDR {cluster_cidr}")
        if len(service_cidr.split(",")) != 2:
            raise ValueError(f"Invalid service CIDR {service_cidr}")
        cluster_ipv4, cluster_ipv6 = cluster_cidr.split(",")
        _validate_cidr(cluster_ipv4, 4)
        _validate_cidr(cluster_ipv6, 6)
        service_ipv4, service_ipv6 = service_cidr.split(",")
        _validate_cidr(service_ipv4, 4)
        _validate_cidr(service_ipv6, 6)
        return

    if len(cluster_cidr.split(",")) != 1:
        raise ValueError(f"Invalid cluster CIDR {cluster_cidr}")
    if len(service_cidr.split(",")) != 1:
        raise ValueError(f"Invalid service CIDR {service_cidr}")

    _validate_cidr(cluster_cidr, 4)
    _validate_cidr(service_cidr, 4)


@required("bootstrap_acme_email", "bootstrap_acme_production_enabled")
def validate_acme_email(email: str, acme_production: bool, **_) -> None:
    try:
        validate_email(email)
    except EmailUndeliverableError:
        pass
    except EmailNotValidError as e:
        raise ValueError(f"Invalid ACME email {email}") from e


@required("bootstrap_flux_github_webhook_token")
def validate_flux_github_webhook_token(token: str, **_) -> None:
    if not re.match(r"^[a-zA-Z0-9]+$", token):
        raise ValueError(f"Invalid Flux GitHub webhook token ***")


@required("bootstrap_cloudflare_domain", "bootstrap_cloudflare_token", "bootstrap_cloudflare_account_tag",
          "bootstrap_cloudflare_tunnel_secret", "bootstrap_cloudflare_tunnel_id")
def validate_cloudflare(domain: str, token: str, account_tag: str, tunnel_secret: str, tunnel_id: str, **_) -> None:
    try:
        cf = CloudFlare.CloudFlare(token=token)
        zones = cf.zones.get(params={"name": domain})
        if not zones:
            raise ValueError(f"Cloudflare domain {domain} not found or token does not have access to it")
    except CloudFlare.exceptions.CloudFlareAPIError as e:
        raise ValueError(f"Cloudflare domain {domain} not found or token does not have access to it") from e
    try:
        request = requests.get(f"https://api.cloudflare.com/client/v4/accounts/{account_tag}/cfd_tunnel/{tunnel_id}",
                               headers={"Authorization": f"Bearer {token}"})
        if request.status_code != 200:
            raise ValueError(f"Cloudflare tunnel for {account_tag} not found or token does not have access to it")
        if not json.loads(request.text)["success"]:
            raise ValueError(f"Cloudflare tunnel for {account_tag} not found or token does not have access to it")
    except requests.exceptions.RequestException as e:
        raise ValueError(f"Cloudflare tunnel for {account_tag} not found or token does not have access to it") from e


@required("bootstrap_dns_server")
def validate_bootstrap_dns_server(dns_server: str, **_) -> None:
    _validate_ip(dns_server)


@required("bootstrap_node_cidr", "bootstrap_kube_api_addr", "bootstrap_k8s_gateway_addr",
          "bootstrap_external_ingress_addr", "bootstrap_internal_ingress_addr")
def validate_host_network(node_cidr: str, api_addr: str, gateway_addr: str, external_ingress_addr: str,
                          internal_ingress_addr: str, **_) -> None:
    _validate_cidr(node_cidr, 4)
    _validate_ip(api_addr)
    _validate_ip(gateway_addr)
    _validate_ip(external_ingress_addr)
    _validate_ip(internal_ingress_addr)

    addrs = [api_addr, gateway_addr, external_ingress_addr, internal_ingress_addr]
    unique = set(addrs)
    if len(addrs) != len(unique):
        raise ValueError(
            f"{api_addr} and {gateway_addr} and {external_ingress_addr} and {internal_ingress_addr} are not unique")

    node_cidr = netaddr.IPNetwork(node_cidr)
    if netaddr.IPAddress(api_addr) not in node_cidr:
        raise ValueError(f"Kubernetes API address {api_addr} is not in the node CIDR {node_cidr}")
    if netaddr.IPAddress(gateway_addr) not in node_cidr:
        raise ValueError(f"Kubernetes gateway address {gateway_addr} is not in the node CIDR {node_cidr}")
    if netaddr.IPAddress(external_ingress_addr) not in node_cidr:
        raise ValueError(
            f"Kubernetes external ingress address {external_ingress_addr} is not in the node CIDR {node_cidr}")
    if netaddr.IPAddress(internal_ingress_addr) not in node_cidr:
        raise ValueError(
            f"Kubernetes internal ingress address {internal_ingress_addr} is not in the node CIDR {node_cidr}")


@required("bootstrap_node_cidr", "bootstrap_nodes", "bootstrap_distribution")
def validate_nodes(node_cidr: str, nodes: dict[list], distribution: str, **_) -> None:
    node_cidr = _validate_cidr(node_cidr, 4)

    masters = nodes.get("master", [])
    if len(masters) < 1:
        raise ValueError(f"Must have at least one master node")
    if len(masters) % 2 == 0:
        raise ValueError(f"Must have an odd number of master nodes")
    for node in masters:
        _validate_node(node, node_cidr, distribution)

    workers = nodes.get("worker", [])
    for node in workers:
        _validate_node(node, node_cidr, distribution)


def massage(data: dict) -> dict:
    data["bootstrap_advanced_flags"] = data.get("bootstrap_advanced_flags", {})
    return data

def validate(data: dict) -> None:
    user_data = massage(data)

    validate_python_version()
    validate_cli_tools(user_data)
    validate_distribution(user_data)
    validate_age(user_data)
    validate_timezone(user_data)
    validate_bootstrap_dns_server(user_data)
    validate_cluster_cidrs(user_data)
    validate_flux_github_webhook_token(user_data)
    validate_host_network(user_data)
    validate_acme_email(user_data)

    if not user_data.get("bootstrap_private_github_repo"):
        validate_github(user_data)

    if not user_data.get("skip_tests", False):
        validate_cloudflare(user_data)
        validate_nodes(user_data)
