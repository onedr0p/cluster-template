"""Unit tests for the cluster.toml validator.

Run from the repo root:
    uv run --locked pytest template/scripts/test_validate.py -q
"""

from pathlib import Path

import json
import sys
import tomllib

import pytest

sys.path.insert(0, str(Path(__file__).parent))

from pydantic import ValidationError  # noqa: E402
from validate import Config, ConfigError, format_errors, load, schema  # noqa: E402

REPO_ROOT = Path(__file__).parents[2]
VALID = sorted((REPO_ROOT / ".github/template-tests/valid").glob("*.toml"))
INVALID = sorted((REPO_ROOT / ".github/template-tests/invalid").glob("*.toml"))

# The error each invalid fixture must be rejected with; a fixture rejected for
# any other reason is not testing what its header says it tests.
INVALID_REASONS = {
    "bad-bgp-asn": r"router_asn: '4294967296' must be in the range 1-4294967295",
    "bad-mac-address": r"nodes\.0\.mac_addr: String should match pattern",
    "bad-repo-url": r"repository\.url: String should match pattern",
    "bad-vlan-tag": r"vlan_tag 5000 must be in the range 1-4094",
    "duplicate-gateway-addrs": r"used by both gateways\.internal and gateways\.dns",
    "duplicate-node-names": r"duplicate node name 'k8s-0' on nodes\[0\] and nodes\[1\]",
    "gateway-node-collision": r"used by both gateways\.internal and nodes\[0\]\.address",
    "missing-dns-token": r"token is required when dns\.provider is 'cloudflare'",
    "missing-external-gateway": r"gateways\.external is required when ingress\.mode is 'cloudflare-tunnel'",
    "missing-known-hosts": r"known_hosts is required for ssh:// URLs to 'git\.example\.com'",
    "missing-schematic": r"nodes\[0\]\.schematic_id is required",
    "nested-cidr-overlap": r"node_cidr 10\.42\.128\.0/17 overlaps kubernetes\.pod_cidr 10\.42\.0\.0/16",
    "node-addr-outside-cidr": r"nodes\[0\]\.address 192\.168\.1\.100 is not inside node_cidr",
    "node-uses-gateway-addr": r"used by both network\.default_gateway and nodes\[0\]\.address",
    "non-canonical-cidr": r"has host bits set; did you mean 10\.10\.10\.0/24",
    "overlapping-cidrs": r"node_cidr 10\.42\.0\.0/16 overlaps kubernetes\.pod_cidr 10\.42\.0\.0/16",
    "partial-bgp": r"partially configured: set router_addr, router_asn and node_asn together \(missing: node_asn\)",
    "reserved-node-name": r"node name 'controller' is reserved",
    "tiny-svc-cidr": r"coredns_addr 10\.43\.0\.10 is not inside svc_cidr 10\.43\.0\.0/29",
    "tunnel-without-dns": r"ingress\.mode 'cloudflare-tunnel' requires dns\.provider 'cloudflare'",
}

# Rejections expressed as one override on a valid fixture:
# (fixture, dotted key, value, expected error).
REJECTIONS = {
    "invalid-cidr": ("private.toml", "network.node_cidr", "10.10.10.0/33", r"'10\.10\.10\.0/33' is not a valid IPv4 CIDR"),
    "default-gateway-outside-node-cidr": ("private.toml", "network.default_gateway", "10.10.11.1", r"default_gateway 10\.10\.11\.1 is not inside node_cidr 10\.10\.10\.0/24"),
    "api-addr-outside-node-cidr": ("private.toml", "kubernetes.api.addr", "10.10.11.254", r"kubernetes\.api\.addr 10\.10\.11\.254 is not inside node_cidr 10\.10\.10\.0/24"),
    "pod-svc-cidr-overlap": ("private.toml", "kubernetes.svc_cidr", "10.42.0.0/16", r"kubernetes\.pod_cidr 10\.42\.0\.0/16 overlaps kubernetes\.svc_cidr 10\.42\.0\.0/16"),
    "token-without-dns-provider": ("internal.toml", "dns.token", "fake", r"token must be empty when dns\.provider is 'none'"),
    "non-decimal-asn": ("public.toml", "cilium.bgp.node_asn", "AS64514", r"'AS64514' must be a decimal ASN"),
    "bad-domain-name": ("private.toml", "domain.name", "Example.com", r"domain\.name: String should match pattern"),
    "bad-tls-san": ("public.toml", "kubernetes.api.tls_sans", ["not a hostname"], r"kubernetes\.api\.tls_sans\.0: String should match pattern"),
    "bad-node-name": ("private.toml", "nodes.0.name", "k8s-0-", r"nodes\.0\.name: String should match pattern"),
    "mtu-too-small": ("private.toml", "nodes.0.mtu", 1449, r"nodes\.0\.mtu: Input should be greater than or equal to 1450"),
    "mtu-too-large": ("private.toml", "nodes.0.mtu", 9001, r"nodes\.0\.mtu: Input should be less than or equal to 9000"),
    "bad-schematic-id": ("private.toml", "nodes.0.schematic_id", "376567", r"nodes\.0\.schematic_id: String should match pattern"),
    "duplicate-mac-address": ("private.toml", "nodes.1.mac_addr", "00:00:00:00:00:00", r"duplicate node MAC address '00:00:00:00:00:00' on nodes\[0\] and nodes\[1\]"),
    "ssh-port-unknown-host": ("private.toml", "repository.url", "ssh://git@git.example.com:2222/k8s/home-ops.git", r"known_hosts is required for ssh:// URLs to 'git\.example\.com'"),
}


def config_from(fixture: str, **overrides) -> dict:
    raw = tomllib.loads((REPO_ROOT / ".github/template-tests/valid" / fixture).read_text())
    for dotted, value in overrides.items():
        target = raw
        *parents, leaf = dotted.split(".")
        for key in parents:
            target = target[int(key)] if isinstance(target, list) else target.setdefault(key, {})
        if value is None:
            target.pop(leaf, None)
        else:
            target[leaf] = value
    return raw


@pytest.mark.parametrize("fixture", VALID, ids=lambda p: p.stem)
def test_valid_fixture_accepted(fixture: Path):
    load(str(fixture))


def test_every_invalid_fixture_has_an_expected_reason():
    assert sorted(INVALID_REASONS) == [p.stem for p in INVALID]


@pytest.mark.parametrize("fixture", INVALID, ids=lambda p: p.stem)
def test_invalid_fixture_rejected(fixture: Path):
    with pytest.raises(ConfigError, match=INVALID_REASONS[fixture.stem]):
        load(str(fixture))


def _load_raw(raw: dict) -> Config:
    try:
        return Config.model_validate(raw)
    except ValidationError as e:
        raise ConfigError(format_errors(e)) from None


@pytest.mark.parametrize(("fixture", "key", "value", "reason"), REJECTIONS.values(), ids=REJECTIONS.keys())
def test_override_rejected(fixture: str, key: str, value, reason: str):
    _load_raw(config_from(fixture))
    with pytest.raises(ConfigError, match=reason):
        _load_raw(config_from(fixture, **{key: value}))


def test_ssh_port_on_bundled_host_needs_no_known_hosts():
    raw = config_from("private.toml", **{"repository.url": "ssh://git@github.com:22/onedr0p/cluster-template.git"})
    assert _load_raw(raw).repository.known_hosts == ""


def test_cluster_issuer_follows_dns_provider():
    public = _load_raw(config_from("public.toml")).model_dump(mode="json")
    assert public["cluster_issuer"] == "letsencrypt-production"
    internal = _load_raw(config_from("internal.toml")).model_dump(mode="json")
    assert internal["cluster_issuer"] == "internal-ca"


def test_default_gateway_derived_from_node_cidr():
    raw = config_from("private.toml")
    assert "default_gateway" not in raw["network"]
    data = _load_raw(raw).model_dump(mode="json")
    assert data["network"]["default_gateway"] == "10.10.10.1"


def test_coredns_addr_default_and_override():
    raw = config_from("private.toml")
    assert _load_raw(raw).model_dump(mode="json")["kubernetes"]["coredns_addr"] == "10.43.0.10"
    raw = config_from("private.toml", **{"kubernetes.coredns_addr": "10.43.0.53"})
    assert _load_raw(raw).model_dump(mode="json")["kubernetes"]["coredns_addr"] == "10.43.0.53"
    raw = config_from("private.toml", **{"kubernetes.coredns_addr": "192.168.9.9"})
    with pytest.raises(ConfigError, match="not inside svc_cidr"):
        _load_raw(raw)


def test_spegel_enabled_follows_node_count():
    two_nodes = config_from("private.toml")
    assert _load_raw(two_nodes).spegel.enabled is True
    one_node = config_from("private.toml")
    one_node["nodes"] = one_node["nodes"][:1]
    assert _load_raw(one_node).spegel.enabled is False
    empty_section = config_from("private.toml", spegel={})
    assert _load_raw(empty_section).spegel.enabled is True
    explicit = config_from("private.toml", **{"spegel.enabled": False})
    assert _load_raw(explicit).spegel.enabled is False


def test_controller_count_ignores_workers():
    raw = config_from("private.toml")
    assert [n["controller"] for n in raw["nodes"]] == [True, False]
    assert _load_raw(raw).controller_count == 1
    raw["nodes"][1]["controller"] = True
    assert _load_raw(raw).controller_count == 2


def test_derived_fields_are_not_settable():
    raw = config_from("public.toml", cilium_bgp_enabled=True)
    with pytest.raises(ConfigError, match="cilium_bgp_enabled"):
        _load_raw(raw)
    raw = config_from("public.toml", controller_count=3)
    with pytest.raises(ConfigError, match="controller_count"):
        _load_raw(raw)


def test_cert_sans_single_source():
    raw = config_from("public.toml")
    assert _load_raw(raw).cert_sans == ["127.0.0.1", "10.10.10.254", "example.com"]
    raw = config_from("private.toml")
    assert _load_raw(raw).cert_sans == ["127.0.0.1", "10.10.10.254"]


def test_ingress_mode_follows_dns_provider():
    cloudflare = config_from("public.toml", ingress=None)
    assert _load_raw(cloudflare).ingress.mode == "cloudflare-tunnel"
    internal = config_from("internal.toml")
    assert (REPO_ROOT / ".github/template-tests/valid/internal.toml").exists()
    assert "ingress" not in internal
    assert _load_raw(internal).ingress.mode == "none"


def test_direct_mode_requires_cloudflare_dns():
    raw = config_from("internal.toml", **{"ingress.mode": "direct"})
    with pytest.raises(ConfigError, match="requires dns.provider 'cloudflare'"):
        _load_raw(raw)


def test_empty_string_means_unset():
    raw = config_from("internal.toml", **{"gateways.external": "", "talos.schematic_id": ""})
    cfg = _load_raw(raw)
    assert cfg.gateways.external is None
    assert cfg.talos.schematic_id is None
    raw = config_from("public.toml")
    raw["nodes"][1]["schematic_id"] = ""
    cfg = _load_raw(raw)
    assert cfg.nodes[1].schematic_id == cfg.talos.schematic_id
    raw = config_from("private.toml", **{"gateways.external": ""})
    with pytest.raises(ConfigError, match="gateways.external is required"):
        _load_raw(raw)


def test_errors_omit_default_factory_noise():
    raw = config_from("public.toml", **{"network.vlan_tag": "5000"})
    with pytest.raises(ConfigError) as excinfo:
        _load_raw(raw)
    assert str(excinfo.value) == "network: vlan_tag 5000 must be in the range 1-4094"


def test_schematic_id_inherits_from_talos_section():
    raw = config_from("public.toml")
    cfg = _load_raw(raw)
    assert cfg.nodes[0].schematic_id == cfg.talos.schematic_id
    assert cfg.nodes[1].schematic_id is not None


def test_node_defaults_exported():
    data = _load_raw(config_from("private.toml")).model_dump(mode="json")
    node = data["nodes"][0]
    assert node["mtu"] == 1500
    assert node["secureboot"] is False
    assert node["kernel_modules"] == []


def test_gateways_may_leave_node_cidr_only_with_bgp():
    with_bgp = config_from("public.toml", **{"gateways.external": "192.168.50.1"})
    _load_raw(with_bgp)  # public.toml enables BGP
    without_bgp = config_from("private.toml", **{"gateways.external": "192.168.50.1"})
    with pytest.raises(ConfigError, match="required unless BGP is enabled"):
        _load_raw(without_bgp)


def test_schema_file_matches_model():
    committed = json.loads((REPO_ROOT / "cluster.schema.json").read_text())
    assert committed == schema(), "cluster.schema.json is stale: run `mise run //template:schema`"


def test_schema_omits_computed_fields():
    assert "cluster_issuer" not in schema()["properties"]
