"""Unit tests for the cluster.toml validator.

Run from the repo root:
    uv run --locked pytest template/scripts/test_validate.py -q
"""

import json
import re
import tomllib
from pathlib import Path

import pytest
from pydantic import ValidationError
from validate import Config, ConfigError, format_errors, load, schema

REPO_ROOT = Path(__file__).parents[2]
VALID = sorted((REPO_ROOT / ".github/template-tests/valid").glob("*.toml"))
INVALID = sorted((REPO_ROOT / ".github/template-tests/invalid").glob("*.toml"))

# The error each invalid fixture must be rejected with; a fixture rejected for
# any other reason is not testing what its header says it tests.
INVALID_REASONS = {
    "bad-bgp-asn": r"router_asn: '4294967296' must be in the range 1-4294967295",
    "bad-mac-address": r"nodes\.0\.mac_addr: String should match pattern",
    "bad-repo-url": r"repository\.url: String should match pattern",
    "bad-vlan-tag": r"network\.vlan_tag: '5000' must be in the range 1-4094",
    "duplicate-gateway-addrs": r"used by both gateways\.internal and gateways\.dns",
    "duplicate-node-names": r"duplicate node name 'k8s-0' on nodes\[0\] and nodes\[1\]",
    "gateway-node-collision": r"used by both gateways\.internal and nodes\[0\]\.address",
    "missing-dns-token": r"token is required when dns\.provider is 'cloudflare'",
    "missing-external-gateway": r"gateways\.external is required when ingress\.mode is 'cloudflare-tunnel'",
    "missing-known-hosts": r"known_hosts is required for ssh:// URLs to 'git\.example\.com'",
    "missing-schematic": r"nodes\[0\]\.schematic_id is required",
    "nested-cidr-overlap": r"node_cidr 10\.42\.128\.0/17 overlaps kubernetes\.pod_cidr 10\.42\.0\.0/16",
    "no-controller": r"at least one node must have controller = true",
    "node-addr-outside-cidr": r"nodes\[0\]\.address 192\.168\.1\.100 is not inside node_cidr",
    "node-uses-gateway-addr": r"used by both network\.default_gateway and nodes\[0\]\.address",
    "non-canonical-cidr": r"has host bits set; did you mean 10\.10\.10\.0/24",
    "overlapping-cidrs": r"node_cidr 10\.42\.0\.0/16 overlaps kubernetes\.pod_cidr 10\.42\.0\.0/16",
    "partial-bgp": r"partially configured: set router_addr, router_asn and node_asn together \(missing: node_asn\)",
    "tiny-svc-cidr": r"coredns_addr 10\.43\.0\.10 is not inside svc_cidr 10\.43\.0\.0/29",
    "tunnel-without-dns": r"ingress\.mode 'cloudflare-tunnel' requires dns\.provider 'cloudflare'",
}

# Rejections expressed as one override on a valid fixture:
# (fixture, dotted key, value, expected error).
REJECTIONS = {
    "invalid-cidr": ("private.toml", "network.node_cidr", "10.10.10.0/33", r"'10\.10\.10\.0/33' is not a valid IPv4 CIDR"),
    "node-cidr-without-prefix": ("private.toml", "network.node_cidr", "10.10.10.0", r"network\.node_cidr: '10\.10\.10\.0' has no prefix length, e\.g\. 10\.10\.10\.0/24"),
    "integer-cidr": ("private.toml", "network.node_cidr", 167772160, r"network\.node_cidr: '167772160' is not a valid IPv4 CIDR"),
    "default-gateway-outside-node-cidr": ("private.toml", "network.default_gateway", "10.10.11.1", r"default_gateway 10\.10\.11\.1 is not inside node_cidr 10\.10\.10\.0/24"),
    "api-addr-outside-node-cidr": ("private.toml", "kubernetes.api.addr", "10.10.11.254", r"kubernetes\.api\.addr 10\.10\.11\.254 is not inside node_cidr 10\.10\.10\.0/24"),
    "pod-svc-cidr-overlap": ("private.toml", "kubernetes.svc_cidr", "10.42.0.0/16", r"kubernetes\.pod_cidr 10\.42\.0\.0/16 overlaps kubernetes\.svc_cidr 10\.42\.0\.0/16"),
    "token-without-dns-provider": ("internal.toml", "dns.token", "fake", r"token must be empty when dns\.provider is 'none'"),
    "non-decimal-asn": ("public.toml", "cilium.bgp.node_asn", "AS64514", r"cilium\.bgp\.node_asn: 'AS64514' is not a decimal number"),
    "bool-vlan-tag": ("public.toml", "network.vlan_tag", True, r"network\.vlan_tag: expected a whole number, got true"),
    "float-vlan-tag": ("public.toml", "network.vlan_tag", 100.0, r"network\.vlan_tag: expected a whole number, got 100\.0"),
    "negative-vlan-tag": ("public.toml", "network.vlan_tag", -5, r"network\.vlan_tag: -5 must be in the range 1-4094"),
    "negative-string-vlan-tag": ("public.toml", "network.vlan_tag", "-5", r"network\.vlan_tag: '-5' is not a decimal number"),
    "zero-padded-zero-vlan-tag": ("public.toml", "network.vlan_tag", "0000", r"network\.vlan_tag: '0000' must be in the range 1-4094"),
    "huge-digit-string-vlan-tag": ("public.toml", "network.vlan_tag", "9" * 5000, r"network\.vlan_tag: '9+' must be in the range 1-4094"),
    "bool-asn": ("public.toml", "cilium.bgp.router_asn", True, r"cilium\.bgp\.router_asn: expected a whole number, got true"),
    "huge-digit-string-asn": ("public.toml", "cilium.bgp.node_asn", "0" * 5000 + "1" * 11, r"cilium\.bgp\.node_asn: '0+1+' must be in the range 1-4294967295"),
    "huge-zero-padded-zero-vlan-tag": ("public.toml", "network.vlan_tag", "0" * 5000, r"network\.vlan_tag: '0+' must be in the range 1-4094"),
    "bad-domain-name": ("private.toml", "domain.name", "Example.com", r"domain\.name: String should match pattern"),
    "bad-tls-san": ("public.toml", "kubernetes.api.tls_sans", ["not a hostname"], r"kubernetes\.api\.tls_sans\.0: 'not a hostname' is not a hostname or IPv4 address"),
    "numeric-tls-san": ("public.toml", "kubernetes.api.tls_sans", ["10.10.10.256"], r"kubernetes\.api\.tls_sans\.0: '10\.10\.10\.256' is not a hostname or IPv4 address"),
    "single-label-domain": ("private.toml", "domain.name", "example", r"domain\.name: String should match pattern"),
    "bad-idn-tld": ("private.toml", "domain.name", "example.xn--abc-", r"domain\.name: String should match pattern"),
    "bad-node-name": ("private.toml", "nodes.0.name", "k8s-0-", r"nodes\.0\.name: String should match pattern"),
    "mtu-too-small": ("private.toml", "nodes.0.mtu", 1449, r"nodes\.0\.mtu: Input should be greater than or equal to 1450"),
    "mtu-too-large": ("private.toml", "nodes.0.mtu", 9001, r"nodes\.0\.mtu: Input should be less than or equal to 9000"),
    "bad-schematic-id": ("private.toml", "nodes.0.schematic_id", "376567", r"nodes\.0\.schematic_id: String should match pattern"),
    "non-hex-schematic-id": ("private.toml", "talos.schematic_id", "z" * 64, r"talos\.schematic_id: String should match pattern '\^\[0-9a-f\]\{64\}\$'"),
    "domain-name-too-long": ("private.toml", "domain.name", ("a" * 63 + ".") * 3 + "a" * 35 + ".com", r"domain\.name: String should have at most 230 characters"),
    "whitespace-dns-token": ("public.toml", "dns.token", " ", r"token is required when dns\.provider is 'cloudflare'"),
    "whitespace-token-without-dns-provider": ("internal.toml", "dns.token", " x ", r"token must be empty when dns\.provider is 'none'"),
    "empty-dns-servers": ("private.toml", "network.dns_servers", [], r"network\.dns_servers: List should have at least 1 item"),
    "empty-ntp-servers": ("private.toml", "network.ntp_servers", [], r"network\.ntp_servers: List should have at least 1 item"),
    "loopback-dns-server": ("private.toml", "network.dns_servers", ["1.1.1.1", "127.0.0.1"], r"network\.dns_servers\[1\] 127\.0\.0\.1 is not usable \(unspecified, loopback or multicast\)"),
    "multicast-ntp-server": ("private.toml", "network.ntp_servers", ["224.0.1.1"], r"network\.ntp_servers\[0\] 224\.0\.1\.1 is not usable"),
    "dns-server-is-k8s-gateway": ("private.toml", "network.dns_servers", ["10.10.10.253"], r"network\.dns_servers\[0\] 10\.10\.10\.253 is gateways\.dns, which only answers once the cluster runs"),
    "ntp-server-is-external-gateway": ("private.toml", "network.ntp_servers", ["10.10.10.251"], r"network\.ntp_servers\[0\] 10\.10\.10\.251 is gateways\.external"),
    "dns-server-is-api-vip": ("private.toml", "network.dns_servers", ["10.10.10.254"], r"10\.10\.10\.254 is kubernetes\.api\.addr, which only answers once the cluster runs"),
    "dns-server-in-svc-cidr": ("private.toml", "network.dns_servers", ["10.43.0.10"], r"network\.dns_servers\[0\] 10\.43\.0\.10 is inside kubernetes\.svc_cidr 10\.43\.0\.0/16"),
    "duplicate-mac-address": ("private.toml", "nodes.1.mac_addr", "00:00:00:00:00:00", r"duplicate node MAC address '00:00:00:00:00:00' on nodes\[0\] and nodes\[1\]"),
    "duplicate-mac-address-dashes": ("private.toml", "nodes.1.mac_addr", "00-00-00-00-00-00", r"duplicate node MAC address '00:00:00:00:00:00' on nodes\[0\] and nodes\[1\]"),
    "empty-disk": ("private.toml", "nodes.0.disk", "", r"nodes\.0\.disk: String should have at least 1 character"),
    "disk-relative-dev-path": ("private.toml", "nodes.0.disk", "dev/nvme0n1", r"'dev/nvme0n1' is a relative path; did you mean '/dev/nvme0n1'\?"),
    "disk-relative-by-id": ("private.toml", "nodes.0.disk", "disk/by-id/nvme-x", r"did you mean '/dev/disk/by-id/nvme-x'\?"),
    "disk-relative-dot-path": ("private.toml", "nodes.0.disk", "./dev/nvme0n1", r"did you mean '/dev/nvme0n1'\?"),
    "api-addr-on-controller-without-opt-out": ("single-node.toml", "kubernetes.api.addr", "10.10.10.100", r"kubernetes\.api\.addr 10\.10\.10\.100 is a node address: .* set kubernetes\.api\.vip = false"),
    "api-addr-on-worker": ("private.toml", "kubernetes.api.addr", "10.10.10.101", r"kubernetes\.api\.addr 10\.10\.10\.101 is a node address"),
    "no-vip-with-unused-addr": ("single-node.toml", "kubernetes.api.vip", False, r"kubernetes\.api\.vip = false requires exactly one controller with kubernetes\.api\.addr set to its address \(controllers: 10\.10\.10\.100\)"),
    "no-vip-with-several-controllers": ("multi-controller.toml", "kubernetes.api.vip", False, r"kubernetes\.api\.vip = false requires exactly one controller"),
    "node-network-address": ("private.toml", "nodes.0.address", "10.10.10.0", r"nodes\[0\]\.address 10\.10\.10\.0 is the network or broadcast address of node_cidr 10\.10\.10\.0/24"),
    "api-broadcast-address": ("private.toml", "kubernetes.api.addr", "10.10.10.255", r"kubernetes\.api\.addr 10\.10\.10\.255 is the network or broadcast address of node_cidr"),
    "coredns-on-api-service-ip": ("private.toml", "kubernetes.coredns_addr", "10.43.0.1", r"coredns_addr 10\.43\.0\.1 is reserved in svc_cidr 10\.43\.0\.0/16"),
    "coredns-on-svc-broadcast": ("private.toml", "kubernetes.coredns_addr", "10.43.255.255", r"coredns_addr 10\.43\.255\.255 is reserved in svc_cidr"),
    "bgp-gateway-in-pod-cidr": ("public.toml", "gateways.external", "10.42.0.5", r"gateways\.external 10\.42\.0\.5 is inside kubernetes\.pod_cidr 10\.42\.0\.0/16"),
    "bgp-gateway-in-svc-cidr": ("public.toml", "gateways.external", "10.43.0.10", r"gateways\.external 10\.43\.0\.10 is inside kubernetes\.svc_cidr 10\.43\.0\.0/16"),
    "bgp-router-addr-collision": ("public.toml", "cilium.bgp.router_addr", "10.10.10.254", r"address 10\.10\.10\.254 is used by both kubernetes\.api\.addr and cilium\.bgp\.router_addr"),
    "bgp-router-addr-node-collision": ("public.toml", "cilium.bgp.router_addr", "10.10.10.100", r"address 10\.10\.10\.100 is used by both nodes\[0\]\.address and cilium\.bgp\.router_addr"),
    "bgp-router-addr-in-pod-cidr": ("public.toml", "cilium.bgp.router_addr", "10.42.0.1", r"cilium\.bgp\.router_addr 10\.42\.0\.1 is inside kubernetes\.pod_cidr 10\.42\.0\.0/16"),
    "whitespace-branch": ("private.toml", "repository.branch", "  ", r"repository\.branch: String should have at least 1 character"),
    "bad-cluster-issuer": ("direct-custom-issuer.toml", "certs.cluster_issuer", "Acme_Production", r"certs\.cluster_issuer: String should match pattern"),
    "reserved-cluster-issuer": ("direct-custom-issuer.toml", "certs.cluster_issuer", "internal-ca", r"certs: cluster_issuer 'internal-ca' is reserved"),
    "ssh-port-unknown-host": ("private.toml", "repository.url", "ssh://git@git.example.com:2222/k8s/home-ops.git", r"known_hosts is required for ssh:// URLs to '\[git\.example\.com\]:2222'"),
    "ssh-custom-port-bundled-host": ("private.toml", "repository.url", "ssh://git@github.com:2222/onedr0p/cluster-template.git", r"known_hosts is required for ssh:// URLs to '\[github\.com\]:2222' \(host keys are only bundled for .* on port 22\)"),
    "known-hosts-wrong-port": ("selfhosted.toml", "repository.url", "ssh://git@git.example.com:2222/k8s/home-ops.git", r"known_hosts has no entry for '\[git\.example\.com\]:2222'; generate it with `ssh-keyscan -p 2222 git\.example\.com`"),
    "known-hosts-wrong-host": ("selfhosted.toml", "repository.url", "ssh://git@git2.example.com/k8s/home-ops.git", r"known_hosts has no entry for 'git2\.example\.com'; generate it with `ssh-keyscan git2\.example\.com`"),
    "known-hosts-junk": ("selfhosted.toml", "repository.known_hosts", "git.example.com", r"known_hosts line 'git\.example\.com' is not '<hosts> <key type> <key>'"),
    "known-hosts-junk-with-bundled-host": ("private.toml", "repository.known_hosts", "github.com ssh-ed25519", r"known_hosts line 'github\.com ssh-ed25519' is not"),
    "branch-with-quote": ("private.toml", "repository.branch", 'ma"in', r"repository\.branch: 'ma\"in' is not a valid git branch name"),
    "branch-with-substitution": ("private.toml", "repository.branch", "${BRANCH}", r"is not a valid git branch name"),
    "branch-with-dotdot": ("private.toml", "repository.branch", "main..dev", r"is not a valid git branch name"),
    "branch-lock-suffix": ("private.toml", "repository.branch", "main.lock", r"is not a valid git branch name"),
    "branch-full-ref": ("private.toml", "repository.branch", "refs/heads/main", r"repository\.branch: 'refs/heads/main' must be a branch name without the 'refs/heads/' prefix"),
    "repo-url-with-quote": ("public.toml", "repository.url", 'https://github.com/onedr0p/home-ops".git', r"repository\.url: .* must not contain whitespace, control characters, double quotes, backslashes or '\$'"),
    "repo-url-with-substitution": ("public.toml", "repository.url", "https://github.com/${OWNER}/home-ops.git", r"repository\.url: .* must not contain whitespace"),
    "dns-token-with-quote": ("public.toml", "dns.token", 'fa"ke', r"dns\.token: 'fa\"ke' must not contain whitespace, control characters, double quotes, backslashes or '\$'"),
    "dns-token-with-substitution": ("public.toml", "dns.token", "${TOKEN}", r"dns\.token: .* must not contain whitespace"),
    "encrypt-disk-without-secureboot": ("private.toml", "nodes.1.secureboot", False, r"nodes\.1: encrypt_disk requires secureboot: TPM disk encryption needs a SecureBoot image"),
    "repo-url-with-credentials": ("public.toml", "repository.url", "https://user:token@github.com/onedr0p/home-ops.git", r"url must not embed credentials"),
    "repo-url-with-token": ("public.toml", "repository.url", "https://token@github.com/onedr0p/home-ops.git", r"url must not embed credentials"),
    "repo-url-scp-style": ("public.toml", "repository.url", "ssh://git@github.com:onedr0p/home-ops.git", r"url host 'github\.com:onedr0p' must be a hostname with an optional numeric port"),
    "repo-url-empty-port": ("public.toml", "repository.url", "https://github.com:/onedr0p/home-ops.git", r"url host 'github\.com:'"),
    "repo-url-extra-user": ("public.toml", "repository.url", "ssh://git@user@github.com/onedr0p/home-ops.git", r"url host 'user@github\.com'"),
    "ebgp-router-outside-node-cidr": ("public.toml", "cilium.bgp.router_addr", "10.10.1.1", r"cilium\.bgp\.router_addr 10\.10\.1\.1 is not inside node_cidr 10\.10\.10\.0/24: an eBGP peer"),
    "pod-cidr-smaller-than-node-block": ("private.toml", "kubernetes.pod_cidr", "10.42.0.0/25", r"kubernetes\.pod_cidr 10\.42\.0\.0/25 is too small: each node gets a /24 from it, so 2 node\(s\) need at least a /23"),
    "pod-cidr-fewer-blocks-than-nodes": ("private.toml", "kubernetes.pod_cidr", "10.42.0.0/24", r"kubernetes\.pod_cidr 10\.42\.0\.0/24 is too small"),
    "bad-kernel-module": ("private.toml", "nodes.0.kernel_modules", ["nvidia]"], r"nodes\.0\.kernel_modules\.0: String should match pattern"),
    "duplicate-kernel-module": ("private.toml", "nodes.0.kernel_modules", ["nvidia", "nvidia"], r"kernel_modules must not contain duplicates"),
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


KNOWN_HOST_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"


# Hashed hosts and patterns are accepted unchecked.
@pytest.mark.parametrize(
    "hosts",
    ["[git.example.com]:2222", "other.example.com,[git.example.com]:2222", "[*.example.com]:2222", "|1|c2FsdA==|aGFzaA=="],
)
def test_known_hosts_entry_for_custom_port_accepted(hosts: str):
    raw = config_from(
        "selfhosted.toml",
        **{
            "repository.url": "ssh://git@git.example.com:2222/k8s/home-ops.git",
            "repository.known_hosts": f"# comment\n\n{hosts} {KNOWN_HOST_KEY}\n",
        },
    )
    _load_raw(raw)


def test_known_hosts_for_bundled_host_on_custom_port():
    raw = config_from(
        "private.toml",
        **{
            "repository.url": "ssh://git@github.com:2222/onedr0p/cluster-template.git",
            "repository.known_hosts": f"[github.com]:2222 {KNOWN_HOST_KEY}",
        },
    )
    _load_raw(raw)


@pytest.mark.parametrize("branch", ["main", "feature/new-thing", "release-1.0", "renovate/flux-2.x", "user@dev"])
def test_branch_names_accepted(branch: str):
    assert _load_raw(config_from("private.toml", **{"repository.branch": branch})).repository.branch == branch


def test_encrypt_disk_with_secureboot_accepted():
    node = _load_raw(config_from("private.toml")).nodes[1]
    assert (node.secureboot, node.encrypt_disk) == (True, True)
    node = _load_raw(config_from("private.toml", **{"nodes.1.encrypt_disk": False, "nodes.1.secureboot": False})).nodes[1]
    assert (node.secureboot, node.encrypt_disk) == (False, False)


def test_ibgp_router_may_leave_node_cidr():
    raw = config_from("public.toml", **{"cilium.bgp.router_addr": "10.10.1.1", "cilium.bgp.node_asn": 64513})
    assert _load_raw(raw).cilium_bgp_enabled is True


def test_pod_cidr_fits_one_block_per_node():
    raw = config_from("private.toml", **{"kubernetes.pod_cidr": "10.42.0.0/23"})
    assert len(raw["nodes"]) == 2
    _load_raw(raw)
    raw["nodes"] = raw["nodes"][:1]
    raw["kubernetes"]["pod_cidr"] = "10.42.0.0/24"
    _load_raw(raw)


@pytest.mark.parametrize("module", ["nvidia-drm", "i2c_dev", "xt_TPROXY"])
def test_kernel_module_names_accepted(module: str):
    raw = config_from("private.toml", **{"nodes.0.kernel_modules": [module]})
    assert _load_raw(raw).nodes[0].kernel_modules == [module]


KERNEL_DISK_NAMES = [
    "sda", "sdb2", "vda", "hdb", "xvda", "nvme0n1", "nvme0n1p1", "nvme0c0n1", "mmcblk0", "mmcblk0p2",
    "mmcblk0boot0", "md0", "md127p1", "loop0", "nbd0", "rbd0", "sr0", "zram0", "pmem0", "pmem0s", "dm-0",
]


@pytest.mark.parametrize("name", KERNEL_DISK_NAMES)
def test_bare_kernel_disk_name_rejected(name: str):
    with pytest.raises(ConfigError, match=rf"'{name}' looks like a kernel device name; use '/dev/{name}', or a /dev/disk/by-id/ path"):
        _load_raw(config_from("private.toml", **{"nodes.0.disk": name}))


@pytest.mark.parametrize(
    ("disk", "whole"),
    [
        ("/dev/sda1", "/dev/sda"),
        ("/dev/nvme0n1p1", "/dev/nvme0n1"),
        ("/dev/disk/by-id/nvme-Samsung_SSD_980_S64DNX0R123456-part1", "/dev/disk/by-id/nvme-Samsung_SSD_980_S64DNX0R123456"),
        ("/dev/disk/by-path/pci-0000:00:1f.2-ata-1-part2", "/dev/disk/by-path/pci-0000:00:1f.2-ata-1"),
    ],
)
def test_partition_disk_rejected(disk: str, whole: str):
    with pytest.raises(ConfigError, match=rf"'{re.escape(disk)}' is a partition; Talos installs to a whole disk, e\.g\. '{re.escape(whole)}'"):
        _load_raw(config_from("private.toml", **{"nodes.0.disk": disk}))


@pytest.mark.parametrize("disk", ["/dev/disk/by-partuuid/0b8f2b5e-01", "/dev/disk/by-partlabel/EFI"])
def test_partition_symlink_disk_rejected(disk: str):
    with pytest.raises(ConfigError, match=rf"'{re.escape(disk)}' is a partition; Talos installs to a whole disk"):
        _load_raw(config_from("private.toml", **{"nodes.0.disk": disk}))


@pytest.mark.parametrize("disk", [" /dev/sda", "S64DNX0R123456 ", "ab\nc", "a\x85b", "a\u2028b", 'ab"c', "ab\\c", "ab: c", "ab #c"])
def test_disk_with_unsafe_characters_rejected(disk: str):
    with pytest.raises(ConfigError, match="must not contain control characters, double quotes, backslashes"):
        _load_raw(config_from("private.toml", **{"nodes.0.disk": disk}))


@pytest.mark.parametrize(
    "disk",
    [
        "/dev/nvme0n1",
        "/dev/sda",
        "/dev/mmcblk0",
        "/dev/md0",
        "/dev/disk/by-id/nvme-Samsung_SSD_980_S64DNX0R123456",
        "/dev/disk/by-id/wwn-0x5002538e40a0b1c2",
        "/dev/disk/by-path/pci-0000:00:1f.2-ata-1",
        "S64DNX0R123456",
        "sdfake-serial-01",
        # Serials are kept verbatim.
        "serial:DATA",
        "RACK/01",
        "WD Blue 1TB",
        "O'Brien-01",
    ],
)
def test_disk_paths_and_serials_accepted(disk: str):
    assert _load_raw(config_from("private.toml", **{"nodes.0.disk": disk})).nodes[0].disk == disk


@pytest.mark.parametrize("mac", ["AA:BB:CC:DD:EE:0F", "aa-bb-cc-dd-ee-0f", " Aa:bB:cc:dd:ee:0f "])
def test_mac_address_normalised(mac: str):
    assert _load_raw(config_from("private.toml", **{"nodes.0.mac_addr": mac})).nodes[0].mac_addr == "aa:bb:cc:dd:ee:0f"


def test_dns_and_ntp_servers_may_be_lan_hosts():
    # The router, a node or a link-local resolver are all reachable at boot.
    raw = config_from("private.toml", **{"network.dns_servers": ["10.10.10.1", "10.10.10.101", "169.254.169.253"], "network.ntp_servers": ["10.10.10.1"]})
    _load_raw(raw)


def test_dns_server_may_reuse_unused_external_gateway_address():
    _load_raw(config_from("internal.toml", **{"network.dns_servers": ["10.10.10.251"]}))


def test_bgp_router_may_be_the_default_gateway():
    raw = config_from("public.toml", **{"cilium.bgp.router_addr": "10.10.10.1"})
    config = _load_raw(raw)
    assert config.cilium.bgp.router_addr == config.network.default_gateway


def test_unused_external_gateway_is_not_checked():
    # Without ingress no envoy-external Gateway uses the address.
    _load_raw(config_from("internal.toml", **{"gateways.external": "10.10.10.100"}))


def test_cluster_issuer_follows_dns_provider():
    public = _load_raw(config_from("public.toml")).model_dump(mode="json")
    assert public["cluster_issuer"] == "letsencrypt-production"
    internal = _load_raw(config_from("internal.toml")).model_dump(mode="json")
    assert internal["cluster_issuer"] == "internal-ca"


NO_ISSUER = {"certs.cluster_issuer": None}


@pytest.mark.parametrize(
    ("fixture", "overrides", "expected"),
    [
        ("public.toml", {}, (True, True, "letsencrypt-production", "letsencrypt-production")),
        ("public.toml", {"ingress.mode": "none"}, (False, True, "letsencrypt-production", "letsencrypt-production")),
        ("cloudflare-custom-issuer.toml", {}, (True, False, "internal-ca", "letsencrypt-dns01")),
        ("direct-custom-issuer.toml", NO_ISSUER, (False, False, "internal-ca", "internal-ca")),
        ("direct-custom-issuer.toml", {}, (False, False, "internal-ca", "acme-production")),
    ],
)
def test_dns_and_issuer_fields(fixture: str, overrides: dict, expected: tuple):
    dumped = _load_raw(config_from(fixture, **overrides)).model_dump(mode="json")
    fields = ("external_dns_enabled", "builtin_acme_issuer", "builtin_issuer", "cluster_issuer")
    assert tuple(dumped[f] for f in fields) == expected


def test_default_gateway_derived_from_node_cidr():
    raw = config_from("private.toml")
    assert "default_gateway" not in raw["network"]
    data = _load_raw(raw).model_dump(mode="json")
    assert data["network"]["default_gateway"] == "10.10.10.1"


def test_coredns_addr_default_and_override():
    kubernetes = _load_raw(config_from("private.toml")).kubernetes
    assert str(kubernetes.coredns_addr) == "10.43.0.10"
    assert kubernetes.coredns_addr_overridden is False
    raw = config_from("private.toml", **{"kubernetes.svc_cidr": "10.96.0.0/12"})
    assert _load_raw(raw).kubernetes.coredns_addr_overridden is False
    # Pinning the default explicitly must not count as an override.
    raw = config_from(
        "private.toml",
        **{"kubernetes.svc_cidr": "10.96.0.0/12", "kubernetes.coredns_addr": "10.96.0.10"},
    )
    assert _load_raw(raw).kubernetes.coredns_addr_overridden is False
    data = _load_raw(config_from("public.toml")).model_dump(mode="json")["kubernetes"]
    assert data["coredns_addr"] == "10.43.0.53"
    assert data["coredns_addr_overridden"] is True
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


def test_at_least_one_controller_required():
    raw = config_from("private.toml", **{"nodes.0.controller": False})
    with pytest.raises(ConfigError, match="at least one node must have controller = true"):
        _load_raw(raw)
    raw["nodes"] = []
    with pytest.raises(ConfigError, match="nodes: List should have at least 1 item"):
        _load_raw(raw)


# TOML integers, decimal strings and zero-padded strings all dump as plain
# ints: these render unquoted into YAML, where a leading zero means octal.
@pytest.mark.parametrize(
    ("vlan_tag", "router_asn", "node_asn"),
    [(100, 64513, 64514), ("100", "64513", "64514"), ("0100", "064513", "064514"), ("0" * 5000 + "100", 64513, 64514)],
)
def test_vlan_and_asn_normalised_to_int(vlan_tag, router_asn, node_asn):
    raw = config_from(
        "public.toml",
        **{"network.vlan_tag": vlan_tag, "cilium.bgp.router_asn": router_asn, "cilium.bgp.node_asn": node_asn},
    )
    data = _load_raw(raw).model_dump(mode="json")
    assert data["network"]["vlan_tag"] == 100
    assert data["cilium"]["bgp"]["router_asn"] == 64513
    assert data["cilium"]["bgp"]["node_asn"] == 64514


def test_vlan_and_asn_integer_range_errors():
    raw = config_from("public.toml", **{"network.vlan_tag": 0})
    with pytest.raises(ConfigError, match="network.vlan_tag: 0 must be in the range 1-4094"):
        _load_raw(raw)
    raw = config_from("public.toml", **{"cilium.bgp.node_asn": 4294967296})
    with pytest.raises(ConfigError, match="node_asn: 4294967296 must be in the range 1-4294967295"):
        _load_raw(raw)


def test_ibgp_asns_accepted():
    raw = config_from("public.toml", **{"cilium.bgp.node_asn": "064513"})
    assert _load_raw(raw).cilium.bgp.node_asn == 64513


def test_dns_token_whitespace_stripped():
    raw = config_from("public.toml", **{"dns.token": "  fake\n"})
    assert _load_raw(raw).dns.token == "fake"
    raw = config_from("internal.toml", **{"dns.token": "  "})
    assert _load_raw(raw).dns.token == ""


def test_repository_whitespace_stripped():
    raw = config_from("private.toml", **{"repository.branch": " main\n"})
    assert _load_raw(raw).repository.branch == "main"
    raw = config_from(
        "private.toml",
        **{"repository.url": "ssh://git@git.example.com/k8s/home-ops.git", "repository.known_hosts": " \n"},
    )
    with pytest.raises(ConfigError, match="known_hosts is required for ssh:// URLs to 'git.example.com'"):
        _load_raw(raw)


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


def test_uses_deploy_key_follows_url_scheme():
    assert _load_raw(config_from("public.toml")).repository.uses_deploy_key is False
    assert _load_raw(config_from("selfhosted.toml")).repository.uses_deploy_key is True
    with pytest.raises(ConfigError, match="uses_deploy_key"):
        _load_raw(config_from("public.toml", **{"repository.uses_deploy_key": True}))


def test_ingress_mode_follows_dns_provider():
    cloudflare = config_from("public.toml", ingress=None)
    assert _load_raw(cloudflare).ingress.mode == "cloudflare-tunnel"
    internal = config_from("internal.toml")
    assert (REPO_ROOT / ".github/template-tests/valid/internal.toml").exists()
    assert "ingress" not in internal
    assert _load_raw(internal).ingress.mode == "none"
    # The sample ships an [ingress] table with mode commented out.
    assert _load_raw(config_from("public.toml", ingress={})).ingress.mode == "cloudflare-tunnel"
    data = _load_raw(config_from("internal.toml", ingress={})).model_dump(mode="json")
    assert data["ingress"]["mode"] == "none"
    assert data["repository"]["webhook_provider"] == "none"


def test_webhook_provider_follows_ingress_mode():
    assert _load_raw(config_from("public.toml")).repository.webhook_provider == "github"
    assert _load_raw(config_from("internal.toml")).repository.webhook_provider == "none"
    # Hosted Git providers reject the internal CA's certificate.
    assert _load_raw(config_from("direct-custom-issuer.toml")).repository.webhook_provider == "github"
    untrusted = config_from("direct-custom-issuer.toml", **NO_ISSUER)
    assert _load_raw(untrusted).repository.webhook_provider == "none"
    lan_git = config_from("internal.toml", **{"repository.webhook_provider": "generic-hmac"})
    assert _load_raw(lan_git).repository.webhook_provider == "generic-hmac"
    assert _load_raw(config_from("internal-webhook.toml")).repository.webhook_provider == "github"
    # Follows ingress.mode, not dns.provider.
    no_ingress = _load_raw(config_from("public.toml", **{"ingress.mode": "none"}))
    assert no_ingress.dns.provider == "cloudflare"
    assert no_ingress.repository.webhook_provider == "none"


def test_single_controller_may_serve_api_on_own_address():
    assert _load_raw(config_from("single-node.toml")).kubernetes.api.vip is True
    cfg = _load_raw(config_from("single-node-no-vip.toml", **{"kubernetes.api.tls_sans": None}))
    assert cfg.kubernetes.api.vip is False
    assert cfg.cert_sans == ["127.0.0.1", "10.10.10.100"]


def test_tls_sans_accept_ip_addresses_without_duplicates():
    sans = ["k8s.example.com", "100.64.0.10", "127.0.0.1", "10.10.10.254", "k8s.example.com"]
    raw = config_from("private.toml", **{"kubernetes.api.tls_sans": sans})
    assert _load_raw(raw).cert_sans == ["127.0.0.1", "10.10.10.254", "k8s.example.com", "100.64.0.10"]


def test_short_hostnames_and_idn_tlds_accepted():
    raw = config_from("private.toml", **{"domain.name": "example.xn--p1ai", "kubernetes.api.tls_sans": ["k8s", "k8s.example.xn--p1ai"]})
    cfg = _load_raw(raw)
    assert cfg.domain.name == "example.xn--p1ai"
    assert cfg.kubernetes.api.tls_sans == ["k8s", "k8s.example.xn--p1ai"]


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


def test_empty_placeholders_fall_back_to_defaults():
    # The sample's `default_gateway = ""`, `vlan_tag = ""` and
    # `coredns_addr = ""` must validate like omitted keys, derived defaults
    # included.
    raw = config_from(
        "private.toml",
        **{"network.default_gateway": "", "network.vlan_tag": "", "kubernetes.coredns_addr": ""},
    )
    data = _load_raw(raw).model_dump(mode="json")
    assert data["network"]["default_gateway"] == "10.10.10.1"
    assert data["network"]["vlan_tag"] is None
    assert data["kubernetes"]["coredns_addr"] == "10.43.0.10"
    raw = config_from("private.toml", **{"kubernetes.svc_cidr": "10.96.0.0/16", "kubernetes.coredns_addr": ""})
    assert _load_raw(raw).model_dump(mode="json")["kubernetes"]["coredns_addr"] == "10.96.0.10"


def test_errors_omit_default_factory_noise():
    raw = config_from("public.toml", **{"network.vlan_tag": "5000"})
    with pytest.raises(ConfigError) as excinfo:
        _load_raw(raw)
    assert str(excinfo.value) == "network.vlan_tag: '5000' must be in the range 1-4094"


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
    with pytest.raises(ConfigError, match="required when cilium.announce is 'l2'"):
        _load_raw(without_bgp)
    unannounced = config_from("private.toml", **{"gateways.external": "192.168.50.1", "cilium.announce": "none"})
    _load_raw(unannounced)


def test_announce_mode_defaults_and_consistency():
    assert _load_raw(config_from("public.toml")).cilium.announce == "bgp"
    assert _load_raw(config_from("private.toml")).cilium.announce == "l2"
    raw = config_from("private.toml", **{"cilium.announce": "bgp"})
    with pytest.raises(ConfigError, match="cilium.announce 'bgp' requires cilium.bgp"):
        _load_raw(raw)
    raw = config_from("public.toml", **{"cilium.announce": "l2"})
    with pytest.raises(ConfigError, match="cilium.bgp is configured but cilium.announce is 'l2'"):
        _load_raw(raw)


def test_gateway_accepts_load_balancer_class():
    raw = config_from("private.toml", **{
        "gateways.internal": {"load_balancer_class": "tailscale"},
        "gateways.external": {"load_balancer_class": "io.cilium/node"},
    })
    cfg = _load_raw(raw)
    assert cfg.gateways.internal.address is None
    assert cfg.gateway_ips == {"gateways.dns": cfg.gateways.dns.address}
    assert cfg.cilium_node_ipam_enabled is True
    assert cfg.gateway_addresses == ["10.10.10.253"]
    data = cfg.model_dump(mode="json")
    assert data["gateways"]["external"] == {"address": None, "load_balancer_class": "io.cilium/node", "node_ports": False}
    assert data["gateways"]["dns"] == {"address": "10.10.10.253", "load_balancer_class": None, "node_ports": False}
    assert _load_raw(config_from("private.toml")).cilium_node_ipam_enabled is False


@pytest.mark.parametrize(
    ("lb_class", "node_ports"),
    [
        ("tailscale", False),
        ("example.com/cloud-lb", True),
    ],
)
def test_gateway_node_ports_only_for_classes_that_need_them(lb_class: str, node_ports: bool):
    raw = config_from("private.toml", **{"gateways.internal": {"load_balancer_class": lb_class}})
    assert _load_raw(raw).gateways.internal.node_ports is node_ports


@pytest.mark.parametrize(
    ("gateways", "lb_uses_nodes"),
    [
        ({}, False),
        ({"gateways.internal": {"load_balancer_class": "tailscale"}}, False),
        ({"gateways.external": {"load_balancer_class": "io.cilium/node"}}, True),
        ({"gateways.internal": {"load_balancer_class": "metallb.io/metallb"}}, True),
    ],
)
def test_lb_uses_nodes(gateways: dict, lb_uses_nodes: bool):
    assert _load_raw(config_from("private.toml", **gateways)).lb_uses_nodes is lb_uses_nodes


def test_lb_uses_nodes_ignores_undeployed_gateways():
    raw = config_from("internal.toml", **{"gateways.external": {"load_balancer_class": "metallb.io/metallb"}})
    assert _load_raw(raw).lb_uses_nodes is False


@pytest.mark.parametrize("gateway", [{}, {"address": "10.10.10.252", "load_balancer_class": "tailscale"}])
def test_gateway_needs_exactly_one_of_address_or_class(gateway):
    raw = config_from("private.toml", **{"gateways.internal": gateway})
    with pytest.raises(ConfigError, match="set exactly one of address or load_balancer_class"):
        _load_raw(raw)


@pytest.mark.parametrize("lb_class", ["not a class", "a" * 64, "example..com/x", "example.com/", "/x"])
def test_gateway_class_must_be_qualified_name(lb_class: str):
    raw = config_from("private.toml", **{"gateways.internal": {"load_balancer_class": lb_class}})
    with pytest.raises(ConfigError, match=r"gateways\.internal\.load_balancer_class: String should match pattern"):
        _load_raw(raw)


def test_gateway_class_prefix_length():
    ok = ".".join(["a" * 63] * 4)[:253]
    _load_raw(config_from("private.toml", **{"gateways.internal": {"load_balancer_class": f"{ok}/x"}}))
    raw = config_from("private.toml", **{"gateways.internal": {"load_balancer_class": f"{ok}a/x"}})
    with pytest.raises(ConfigError, match="the prefix must be at most 253 characters"):
        _load_raw(raw)


@pytest.mark.parametrize("lb_class", ["io.cilium/l2-announcer", "io.cilium/bgp-control-plane"])
def test_gateway_class_rejects_cilium_lb_ipam(lb_class: str):
    raw = config_from("private.toml", **{"gateways.internal": {"load_balancer_class": lb_class}})
    with pytest.raises(ConfigError, match="is Cilium's own LB IPAM: set an address instead"):
        _load_raw(raw)


def test_one_envoy_gateway_on_node_ipam():
    node = {"load_balancer_class": "io.cilium/node"}
    raw = config_from("private.toml", **{"gateways.internal": node, "gateways.external": node})
    with pytest.raises(ConfigError, match=r"gateways\.internal and gateways\.external both use load_balancer_class 'io\.cilium/node'"):
        _load_raw(raw)
    # k8s-gateway listens on :53 only, and without ingress there is no
    # envoy-external.
    _load_raw(config_from("private.toml", **{"gateways.internal": node, "gateways.dns": node}))
    _load_raw(config_from("internal.toml", **{"gateways.internal": node, "gateways.external": node}))


def test_external_gateway_unused_without_ingress():
    raw = config_from("internal.toml", **{"gateways.external": {"load_balancer_class": "io.cilium/node"}})
    cfg = _load_raw(raw)
    assert "external" not in cfg.deployed_gateways
    assert cfg.cilium_node_ipam_enabled is False
    raw = config_from("internal.toml", **{"gateways.external": "10.10.10.251"})
    assert "10.10.10.251" not in _load_raw(raw).gateway_addresses


@pytest.mark.parametrize("addr", ["0.0.0.0", "127.0.0.1", "169.254.1.1", "224.0.0.1", "255.255.255.255"])
def test_unannounced_gateway_must_be_routable(addr: str):
    raw = config_from("private.toml", **{"gateways.external": addr, "cilium.announce": "none"})
    with pytest.raises(ConfigError, match=rf"gateways\.external {re.escape(addr)} is not routable"):
        _load_raw(raw)


def test_cilium_networks_needed():
    assert _load_raw(config_from("private.toml")).cilium_networks_needed is True
    raw = config_from("private.toml", **{"cilium.announce": "none"})
    assert _load_raw(raw).cilium_networks_needed is True  # the pool
    assert _load_raw(config_from("lb-class.toml")).cilium_networks_needed is False


def test_schema_file_matches_model():
    committed = json.loads((REPO_ROOT / "cluster.schema.json").read_text())
    assert committed == schema(), "cluster.schema.json is stale: run `mise run //template:schema`"


def test_schema_omits_computed_fields():
    assert "cluster_issuer" not in schema()["properties"]
