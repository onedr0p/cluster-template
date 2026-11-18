"""Tests for the output rendered from the cluster.toml in the repo root.

Render the tree first:
    mise run configure
    mise run //talos:render
    mise run //template:test-render
"""

from functools import cache
from ipaddress import ip_network
from pathlib import Path

import sys

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent))

from validate import load  # noqa: E402

REPO_ROOT = Path(__file__).parents[2]
CONFIG_FILE = REPO_ROOT / "cluster.toml"

# A clean checkout has no cluster.toml; the E2E job always creates one first.
pytestmark = pytest.mark.skipif(not CONFIG_FILE.exists(), reason="no cluster.toml to render from")


# cluster.toml and the machine configs hold secrets, and pytest prints the
# arguments of a failing test, so tests call these instead of taking fixtures.
@cache
def config() -> dict:
    return load(str(CONFIG_FILE))


# The documents of one kind in a rendered file. PyYAML quotes the source in
# its errors for a string, but not for a stream.
def documents(path: str, kind: str) -> list[dict]:
    with (REPO_ROOT / path).open() as stream:
        return [doc for doc in yaml.safe_load_all(stream) if doc.get("kind") == kind]


def machine_config(node: dict, kind: str) -> list[dict]:
    return documents(f"talos/rendered/{node['name']}.yaml", kind)


# Controllers announce kubernetes.api.addr as a Layer 2 VIP unless
# kubernetes.api.vip = false.
def test_api_vip_announced_by_controllers_only():
    api = config()["kubernetes"]["api"]
    for node in config()["nodes"]:
        vips = [doc["name"] for doc in machine_config(node, "Layer2VIPConfig")]
        assert vips == ([api["addr"]] if api["vip"] and node["controller"] else []), node["name"]


# Talos points the kubelet at the 10th Service IP unless clusterDNS is set,
# and it appends to list fields, so clusterDNS is only rendered when CoreDNS
# uses another address. That default is derived here independently of
# validate.py on purpose.
def test_kubelet_cluster_dns_matches_coredns_service():
    (release,) = documents("kubernetes/apps/kube-system/coredns/app/helmrelease.yaml", "HelmRelease")
    coredns = release["spec"]["values"]["service"]["clusterIP"]
    for node in config()["nodes"]:
        (network,) = machine_config(node, "KubeNetworkConfig")
        (kubelet,) = machine_config(node, "KubeletConfig")
        default = str(ip_network(network["serviceSubnets"][0])[10])
        assert kubelet.get("clusterDNS", []) == ([] if coredns == default else [coredns]), node["name"]


# A Git host reaches the webhook through envoy-external, which only exists
# with an ingress mode; an internal-only cluster serves it on envoy-internal.
def test_flux_webhook_route_attaches_to_the_reachable_gateway():
    if config()["repository"]["webhook_provider"] == "none":
        pytest.skip("no webhook route without a webhook provider")
    (route,) = documents("kubernetes/apps/flux-system/flux-instance/app/httproute.yaml", "HTTPRoute")
    gateways = documents("kubernetes/apps/network/envoy-gateway/app/envoy.yaml", "Gateway")
    expected = "envoy-internal" if config()["ingress"]["mode"] == "none" else "envoy-external"
    assert [ref["name"] for ref in route["spec"]["parentRefs"]] == [expected]
    assert expected in [gateway["metadata"]["name"] for gateway in gateways]
