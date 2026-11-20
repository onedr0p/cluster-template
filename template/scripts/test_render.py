"""Tests for the output rendered from the cluster.toml in the repo root.

Render the tree first:
    mise run configure
    mise run //talos:render
    mise run //template:test-render
"""

import tomllib
from functools import cache
from ipaddress import ip_network
from pathlib import Path

import pytest
import yaml
from validate import load

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


# Only ssh:// repositories authenticate with the deploy key: the Secret is
# rendered, apps-secrets applies it and flux-instance pulls with it. The
# scheme is read from the URL here independently of validate.py on purpose.
def test_deploy_key_follows_the_repository_scheme():
    ssh = config()["repository"]["url"].startswith("ssh://")
    tasks = tomllib.loads((REPO_ROOT / "bootstrap/mise.toml").read_text())["tasks"]
    applied = [line.strip(" \\") for line in tasks["apps-secrets"]["run"].splitlines()]
    (release,) = documents("kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml", "HelmRelease")
    assert (REPO_ROOT / "bootstrap/deploy-key.sops.yaml").exists() == ssh
    assert ("deploy-key.sops.yaml" in applied) == ssh
    assert release["spec"]["values"]["instance"]["sync"].get("pullSecret") == ("deploy-key" if ssh else None)


# A custom issuer issues the wildcard Certificate, but it usually lives in a
# Kustomization that depends on cert-manager, so cert-manager's health check
# must name an issuer the template renders. The built-in issuer is derived
# here independently of validate.py on purpose.
def test_wildcard_certificate_issuer():
    custom = config()["certs"]["cluster_issuer"]
    acme = config()["dns"]["provider"] == "cloudflare" and not custom
    builtin = "letsencrypt-production" if acme else "internal-ca"
    app = "kubernetes/apps/cert-manager/cert-manager/app"
    rendered = [doc["metadata"]["name"] for doc in documents(f"{app}/clusterissuer.yaml", "ClusterIssuer")]
    (kustomization,) = documents("kubernetes/apps/cert-manager/cert-manager/ks.yaml", "Kustomization")
    checked = [check["name"] for check in kustomization["spec"]["healthChecks"] if check["kind"] == "ClusterIssuer"]
    (certificate,) = documents("kubernetes/apps/network/envoy-gateway/app/certificate.yaml", "Certificate")
    assert checked == [builtin]
    assert builtin in rendered
    assert certificate["spec"]["issuerRef"]["name"] == (custom or builtin)


# Only cloudflare-dns (external-dns) publishes public records, so its
# Kustomization and its CRD release need Cloudflare DNS and an ingress mode.
def test_external_dns_follows_the_dns_provider():
    expected = config()["dns"]["provider"] == "cloudflare" and config()["ingress"]["mode"] != "none"
    (network,) = documents("kubernetes/apps/network/kustomization.yaml", "Kustomization")
    with (REPO_ROOT / "bootstrap/helmfile/crds.yaml").open() as stream:
        releases = [release["name"] for release in yaml.safe_load(stream)["releases"]]
    assert ("./cloudflare-dns/ks.yaml" in network["resources"]) == expected
    assert ("cloudflare-dns" in releases) == expected


# The parsed YAML holds exactly the configured strings; a kernel module named
# like a number must stay a string.
def test_cluster_toml_strings_rendered_verbatim():
    repository = config()["repository"]
    (release,) = documents("kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml", "HelmRelease")
    sync = release["spec"]["values"]["instance"]["sync"]
    assert (sync["url"], sync["ref"]) == (repository["url"], f"refs/heads/{repository['branch']}")
    for node in config()["nodes"]:
        modules = [doc["name"] for doc in machine_config(node, "KernelModuleConfig")]
        assert modules == node["kernel_modules"], node["name"]
