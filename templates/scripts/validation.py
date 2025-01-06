from functools import wraps
from typing import Callable
import dns.resolver
import netaddr
import ntplib
import re
import socket
import sys


def get_nested_value(data: dict, key: str):
    keys = key.split(".")
    for k in keys:
        data = data.get(k)
        if data is None:
            return None
    return data


def required(*keys: str):
    def wrapper_outter(func: Callable):
        @wraps(func)
        def wrapper(data: dict, *_, **kwargs) -> None:
            for key in keys:
                if get_nested_value(data, key) is None:
                    raise ValueError(f"Missing required key {key}")
            return func(*[get_nested_value(data, key) for key in keys], **kwargs)
        return wrapper
    return wrapper_outter


def validate_python_version() -> None:
    required_version = (3, 11, 0)
    if sys.version_info < required_version:
        raise ValueError(f"Invalid Python version {sys.version_info}, must be 3.11 or higher")


@required("cluster.nodes.dns")
def validate_dns_servers(servers: list = ["1.1.1.1","1.0.0.1"], **_) -> None:
    resolver = dns.resolver.Resolver()
    resolver.nameservers = servers
    resolver.timeout = 5
    resolver.lifetime = 5

    try:
        resolver.resolve("cloudflare.com")
    except Exception as e:
        raise ValueError(f"Unable to resolve cloudflare.com with DNS servers {servers}") from e


@required("cluster.nodes.ntp")
def validate_ntp_servers(servers: list = ["162.159.200.1","162.159.200.123"], **_) -> None:
    client = ntplib.NTPClient()
    for server in servers:
        try:
            client.request(server, version=3)
        except Exception as e:
            raise ValueError(f"Unable to connect to NTP server {server}") from e


def validate(data: dict) -> None:
    validate_python_version()

    validate_dns_servers(data)
    validate_ntp_servers(data)
