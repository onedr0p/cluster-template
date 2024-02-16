from functools import wraps
from shutil import which
from typing import Callable
from zoneinfo import available_timezones
import netaddr
import sys

DISTRIBUTIONS = ["k3s", "talos"]
GLOBAL_CLI_TOOLS = ["age", "cloudflared", "flux", "helmfile", "sops", "jq", "kubeconform", "kustomize"]
TALOS_CLI_TOOLS = ["talosctl", "talhelper"]

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


def validate_python_version() -> None:
    required_version = (3, 11, 0)
    if sys.version_info < required_version:
        raise ValueError(f"Python version is below 3.11. Please upgrade.")


@required("bootstrap_distribution")
def validate_cli_tools(distribution: dict, **_) -> None:
    if distribution not in DISTRIBUTIONS:
        raise ValueError(f"Invalid distribution {distribution}")
    for tool in GLOBAL_CLI_TOOLS:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")
    for tool in TALOS_CLI_TOOLS if distribution in ["talos"] else []:
        if not which(tool):
            raise ValueError(f"Missing required CLI tool {tool}")


@required("bootstrap_distribution")
def validate_distribution(distribution: dict, **_) -> None:
    if distribution not in DISTRIBUTIONS:
        raise ValueError(f"Invalid distribution {distribution}")


@required("bootstrap_timezone")
def validate_timezone(timezone: str, **_) -> None:
    if timezone not in available_timezones():
        raise ValueError(f"Invalid timezone {timezone}")


def validate(data: dict) -> None:
    validate_python_version()
    validate_cli_tools(data)
    validate_distribution(data)
    validate_timezone(data)
