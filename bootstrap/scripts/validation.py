from functools import wraps
from shutil import which
from typing import Callable
from zoneinfo import available_timezones
import netaddr
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


def _validate_network(network: str, family: int) -> str:
    try:
        network = netaddr.IPNetwork(network)
        if network.version != family:
            raise ValueError(f"Invalid network family {network.version}")
    except netaddr.core.AddrFormatError as e:
        raise ValueError(f"Invalid network {network}") from e
    return network


def validate_python_version() -> None:
    required_version = (3, 11, 0)
    if sys.version_info < required_version:
        raise ValueError(f"Python version is below 3.11. Please upgrade.")


@required("distribution")
def validate_cli_tools(distribution: str, **_) -> None:
    if distribution not in DISTRIBUTIONS:
        raise ValueError(f"Invalid distribution {distribution}")
    for tool in GLOBAL_CLI_TOOLS:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")
    for tool in TALOS_CLI_TOOLS if distribution in ["talos"] else []:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")
    for tool in K0S_CLI_TOOLS if distribution in ["k0s"] else []:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")


@required("distribution")
def validate_distribution(distribution: str, **_) -> None:
    if distribution not in DISTRIBUTIONS:
        raise ValueError(f"Invalid distribution {distribution}")


@required("timezone")
def validate_timezone(timezone: str, **_) -> None:
    if timezone not in available_timezones():
        raise ValueError(f"Invalid timezone {timezone}")


@required("cluster", "feature_gates")
def validate_cluster_networks(cluster: dict, feature_gates: dict, **_) -> None:
    dual_stack_ipv4_first = feature_gates.get("dual_stack_ipv4_first", False)
    pod_network = cluster.get("pod_network")
    service_network = cluster.get("service_network")

    if pod_network == service_network:
        raise ValueError(f"Pod network {pod_network} is the same as service network {service_network}")

    if dual_stack_ipv4_first:
        if len(pod_network.split(",")) != 2:
            raise ValueError(f"Invalid pod network {pod_network}")
        if len(service_network.split(",")) != 2:
            raise ValueError(f"Invalid service network {service_network}")
        cluster_ipv4, cluster_ipv6 = pod_network.split(",")
        _validate_network(cluster_ipv4, 4)
        _validate_network(cluster_ipv6, 6)
        service_ipv4, service_ipv6 = service_network.split(",")
        _validate_network(service_ipv4, 4)
        _validate_network(service_ipv6, 6)
        return

    if len(pod_network.split(",")) != 1:
        raise ValueError(f"Invalid pod network {pod_network}")
    if len(service_network.split(",")) != 1:
        raise ValueError(f"Invalid service network {service_network}")

    _validate_network(pod_network, 4)
    _validate_network(service_network, 4)


def massage_config(data: dict) -> dict:
    data["flux"] = data.get("flux", {})
    data["cloudflare"] = data.get("cloudflare", {})
    data["feature_gates"] = data.get("feature_gates", {})
    return data


def validate(data: dict) -> None:
    user_config = massage_config(data)

    validate_python_version()
    validate_cli_tools(user_config)
    validate_distribution(user_config)
    validate_timezone(user_config)
    validate_cluster_networks(user_config)
