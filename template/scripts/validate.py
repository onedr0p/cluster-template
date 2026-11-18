"""Validate cluster.toml, apply defaults, and emit the config as JSON.

Standalone usage (doctor, CI): uv run --locked --no-dev template/scripts/validate.py [cluster.toml]
Schema export (mise run //template:schema): uv run --locked --no-dev template/scripts/validate.py --schema
In-process usage (makejinja plugin): from validate import load

Exits non-zero with one human-readable error per line on stderr when the
config is invalid.
"""

from ipaddress import IPv4Address, IPv4Network
from pathlib import Path
from typing import Annotated, Any, Literal, Self

import json
import re
import sys
import tomllib

from pydantic_core import PydanticUseDefault
from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    ValidationError,
    WithJsonSchema,
    computed_field,
    field_validator,
    model_validator,
)

# Git hosts whose SSH host keys are bundled with the template; ssh:// URLs
# pointing anywhere else must provide repository.known_hosts.
KNOWN_SSH_HOSTS = ["github.com", "gitlab.com", "codeberg.org"]

REPO_URL_PATTERN = r"^(https?://|ssh://git@)[^/]+/.+$"
# A Kubernetes qualified name, as used by Service.spec.loadBalancerClass:
# an optional DNS subdomain prefix (at most 253 characters, checked in
# _lb_class) and a name of at most 63 characters.
DNS_LABEL = r"[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?"
LB_CLASS_PATTERN = rf"^({DNS_LABEL}(\.{DNS_LABEL})*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{{0,61}}[A-Za-z0-9])?$"
# Cilium's own LB IPAM classes; gateways get LB IPAM through an address.
CILIUM_LB_IPAM_CLASSES = ["io.cilium/l2-announcer", "io.cilium/bgp-control-plane"]
FQDN_PATTERN = r"^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$"


def _network(value: Any) -> Any:
    """Parse a CIDR, requiring network-address form (no host bits set)."""
    if not isinstance(value, str):
        return value
    try:
        return IPv4Network(value)
    except ValueError:
        try:
            fixed = IPv4Network(value, strict=False)
        except ValueError:
            raise ValueError(f"{value!r} is not a valid IPv4 CIDR") from None
        raise ValueError(
            f"{value!r} has host bits set; did you mean {fixed}?"
        ) from None


# TOML integers are accepted as well as decimal strings and normalised to a
# string. bool is rejected explicitly because it is a subclass of int.
def _int_to_str(value: Any) -> Any:
    if isinstance(value, bool):
        raise ValueError(f"expected a number, got {str(value).lower()}")
    return str(value) if isinstance(value, int) else value


def _asn(value: str) -> str:
    if value == "":
        return value
    if not re.fullmatch(r"[0-9]+", value):
        raise ValueError(f"{value!r} must be a decimal ASN")
    if not 1 <= int(value) <= 4294967295:
        raise ValueError(f"{value!r} must be in the range 1-4294967295")
    # Strip leading zeros: the value is rendered unquoted into YAML, where
    # "064514" would be read as octal.
    return str(int(value))


# IPv4Address | Fqdn would report two errors with an unreadable union path;
# one message naming both accepted forms is clearer.
def _san(value: str) -> str:
    try:
        IPv4Address(value)
    except ValueError:
        if len(value) > 253 or not re.fullmatch(FQDN_PATTERN, value):
            raise ValueError(f"{value!r} is not a hostname or IPv4 address") from None
    return value


def _empty_to_none(value: Any) -> Any:
    return None if value == "" else value


def _lb_class(value: str) -> str:
    prefix, _, _ = value.rpartition("/")
    if len(prefix) > 253:
        raise ValueError(f"{value!r}: the prefix must be at most 253 characters")
    if value in CILIUM_LB_IPAM_CLASSES:
        raise ValueError(
            f"{value!r} is Cilium's own LB IPAM: set an address instead "
            "(cilium.announce selects L2 or BGP)"
        )
    return value


# For fields whose default is derived from other fields: "" falls back to that
# default (including a default_factory) instead of failing validation.
def _empty_to_default(value: Any) -> Any:
    if value == "":
        raise PydanticUseDefault()
    return value


type Cidr = Annotated[IPv4Network, BeforeValidator(_network)]
type Asn = Annotated[
    str,
    BeforeValidator(_int_to_str, json_schema_input_type=str | int),
    AfterValidator(_asn),
]
type Fqdn = Annotated[str, Field(pattern=FQDN_PATTERN, max_length=253)]
type San = Annotated[
    str,
    AfterValidator(_san),
    WithJsonSchema(
        {"anyOf": [{"type": "string", "format": "ipv4"}, {"type": "string", "pattern": FQDN_PATTERN, "maxLength": 253}]}
    ),
]
type SchematicId = Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
type DecimalString = Annotated[str, Field(pattern=r"^[0-9]+$")]
type VlanTag = Annotated[
    DecimalString,
    BeforeValidator(_int_to_str, json_schema_input_type=DecimalString | int),
]

# An empty string means unset, so placeholders left in cluster.toml validate
# the same as an omitted key.
type OptionalSchematicId = Annotated[
    SchematicId | None,
    BeforeValidator(_empty_to_none, json_schema_input_type=SchematicId | Literal[""] | None),
]
type OptionalVlanTag = Annotated[
    VlanTag | None,
    BeforeValidator(_empty_to_none, json_schema_input_type=VlanTag | Literal[""] | None),
]
type DefaultedIPv4Address = Annotated[
    IPv4Address,
    BeforeValidator(_empty_to_default, json_schema_input_type=IPv4Address | Literal[""]),
]


class Model(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Network(Model):
    node_cidr: Cidr
    dns_servers: list[IPv4Address] = Field(
        default=[IPv4Address("1.1.1.1"), IPv4Address("1.0.0.1")], min_length=1
    )
    ntp_servers: list[IPv4Address] = Field(
        default=[IPv4Address("162.159.200.1"), IPv4Address("162.159.200.123")], min_length=1
    )
    # The first IP in node_cidr unless set explicitly.
    default_gateway: DefaultedIPv4Address = Field(
        default_factory=lambda data: data["node_cidr"].network_address + 1
    )
    vlan_tag: OptionalVlanTag = None

    # Strip leading zeros: the tag is rendered unquoted into YAML, where
    # "0100" would be read as octal (VLAN 64).
    @field_validator("vlan_tag")
    @classmethod
    def _decimal_vlan_tag(cls, value: str | None) -> str | None:
        return None if value is None else str(int(value))

    @model_validator(mode="after")
    def check(self) -> Self:
        if self.default_gateway not in self.node_cidr:
            raise ValueError(
                f"default_gateway {self.default_gateway} is not inside node_cidr {self.node_cidr}"
            )
        if self.vlan_tag is not None and not 1 <= int(self.vlan_tag) <= 4094:
            raise ValueError(f"vlan_tag {self.vlan_tag} must be in the range 1-4094")
        return self


class Api(Model):
    addr: IPv4Address
    # False serves the API on the sole controller's own address (addr)
    # instead of announcing a Layer 2 VIP.
    vip: bool = True
    tls_sans: list[San] | None = None


# Talos points kubelet's clusterDNS at the 10th IP of the service subnet.
def _talos_cluster_dns(svc_cidr: IPv4Network) -> IPv4Address:
    return svc_cidr.network_address + 10


class Kubernetes(Model):
    pod_cidr: Cidr = IPv4Network("10.42.0.0/16")
    svc_cidr: Cidr = IPv4Network("10.43.0.0/16")
    # Talos's default unless set explicitly.
    coredns_addr: DefaultedIPv4Address = Field(
        default_factory=lambda data: _talos_cluster_dns(data["svc_cidr"])
    )
    api: Api

    # Gates clusterDNS in talos/all/30-kubelet.yaml.
    @computed_field
    @property
    def coredns_addr_overridden(self) -> bool:
        return self.coredns_addr != _talos_cluster_dns(self.svc_cidr)

    @model_validator(mode="after")
    def check(self) -> Self:
        if self.coredns_addr not in self.svc_cidr:
            raise ValueError(
                f"coredns_addr {self.coredns_addr} is not inside svc_cidr {self.svc_cidr}"
            )
        # The apiserver always takes the first service IP for the kubernetes
        # Service; the network and broadcast addresses are not allocatable.
        reserved = {
            self.svc_cidr.network_address,
            self.svc_cidr.network_address + 1,
            self.svc_cidr.broadcast_address,
        }
        if self.coredns_addr in reserved:
            raise ValueError(
                f"coredns_addr {self.coredns_addr} is reserved in svc_cidr {self.svc_cidr} "
                "(network, broadcast or kubernetes API service address)"
            )
        return self


class Gateway(Model):
    model_config = ConfigDict(
        json_schema_extra={"oneOf": [{"required": ["address"]}, {"required": ["load_balancer_class"]}]}
    )

    # Either a LoadBalancer IP that Cilium LB IPAM assigns (and announces
    # per cilium.announce), or the loadBalancerClass of another
    # implementation, e.g. "io.cilium/node" to serve on the nodes' own IPs
    # or "tailscale" for the Tailscale Kubernetes operator.
    address: IPv4Address | None = None
    load_balancer_class: Annotated[str, Field(pattern=LB_CLASS_PATTERN), AfterValidator(_lb_class)] | None = None

    @model_validator(mode="after")
    def check(self) -> Self:
        if (self.address is None) == (self.load_balancer_class is None):
            raise ValueError("set exactly one of address or load_balancer_class")
        return self


def _gateway(value: Any) -> Any:
    """A bare string is shorthand for {address = "<ip>"}."""
    return {"address": value} if isinstance(value, str) else value


def _optional_gateway(value: Any) -> Any:
    return _gateway(_empty_to_none(value))


type GatewaySpec = Annotated[
    Gateway,
    BeforeValidator(_gateway, json_schema_input_type=IPv4Address | Gateway),
]
type OptionalGatewaySpec = Annotated[
    Gateway | None,
    BeforeValidator(_optional_gateway, json_schema_input_type=IPv4Address | Gateway | Literal[""] | None),
]


class Gateways(Model):
    internal: GatewaySpec
    dns: GatewaySpec
    # Required when ingress.mode is not "none".
    external: OptionalGatewaySpec = None


class Repository(Model):
    url: str = Field(pattern=REPO_URL_PATTERN)
    branch: str = Field(default="main", min_length=1)
    webhook_provider: Literal["github", "gitlab", "generic-hmac", "none"] | None = Field(
        default=None,
        description='Defaults to "github", or "none" when ingress.mode is "none".',
    )
    known_hosts: str = ""

    @model_validator(mode="after")
    def check(self) -> Self:
        if self.url.startswith("ssh://"):
            host = self.url.removeprefix("ssh://git@").split("/", 1)[0].split(":", 1)[0]
            if host not in KNOWN_SSH_HOSTS and not self.known_hosts:
                raise ValueError(
                    f"known_hosts is required for ssh:// URLs to {host!r} "
                    f"(host keys are only bundled for {', '.join(KNOWN_SSH_HOSTS)})"
                )
        return self


class Domain(Model):
    name: Fqdn


class Dns(Model):
    provider: Literal["cloudflare", "none"] = "cloudflare"
    token: str = ""

    # Surrounding whitespace is never part of a token (and a whitespace-only
    # token is not a token), so strip it before the checks below.
    @field_validator("token")
    @classmethod
    def _strip_token(cls, value: str) -> str:
        return value.strip()

    @model_validator(mode="after")
    def check(self) -> Self:
        if self.provider == "cloudflare" and not self.token:
            raise ValueError("token is required when dns.provider is 'cloudflare'")
        if self.provider == "none" and self.token:
            raise ValueError("token must be empty when dns.provider is 'none'")
        return self


class Ingress(Model):
    mode: Literal["cloudflare-tunnel", "direct", "none"] = "cloudflare-tunnel"


class Bgp(Model):
    router_addr: IPv4Address | Literal[""] = ""
    router_asn: Asn = ""
    node_asn: Asn = ""

    @property
    def unset(self) -> list[str]:
        return [name for name in ("router_addr", "router_asn", "node_asn") if getattr(self, name) == ""]

    @property
    def configured(self) -> bool:
        return not self.unset

    @model_validator(mode="after")
    def check(self) -> Self:
        unset = self.unset
        if unset and len(unset) < 3:
            raise ValueError(
                "bgp is partially configured: set router_addr, router_asn and "
                f"node_asn together (missing: {', '.join(unset)})"
            )
        return self


class Talos(Model):
    # Default Image Factory schematic for nodes that don't set their own.
    schematic_id: OptionalSchematicId = None


class Spegel(Model):
    # True when the cluster has more than one node, unless set explicitly.
    enabled: bool | None = None


class Cilium(Model):
    loadbalancer_mode: Literal["dsr", "snat"] = "dsr"
    # How gateway addresses become reachable: "l2" answers ARP for them on
    # node_cidr, "bgp" additionally advertises them to cilium.bgp's router,
    # "none" announces nothing (the network must route them to the nodes).
    # Defaults to "bgp" when cilium.bgp is configured, otherwise "l2".
    announce: Literal["l2", "bgp", "none"] | None = None
    bgp: Bgp = Bgp()


# Kernel block device names (optionally with a partition suffix). A disk value
# without a leading "/" is matched against the disk serial, so a bare device
# name would select no disk and the install would never start.
KERNEL_DISK_NAME = re.compile(
    r"^(?:(?:s|v|h|xv)d[a-z]+\d*|nvme\d+n\d+(?:p\d+)?|mmcblk\d+(?:p\d+)?)$"
)


def _disk(value: str) -> str:
    if not value:
        raise ValueError("disk must be a device path, a /dev/disk/by-id/ path or a disk serial")
    if KERNEL_DISK_NAME.match(value):
        raise ValueError(
            f"{value!r} looks like a kernel device name, not a disk serial; "
            f"did you mean '/dev/{value}'?"
        )
    return value


class Node(Model):
    name: str = Field(pattern=r"^[a-z0-9][a-z0-9\-]{0,61}[a-z0-9]$|^[a-z0-9]$")
    address: IPv4Address
    controller: bool
    # A value starting with "/" is a device path or symlink; anything else is
    # matched against the disk serial.
    disk: Annotated[str, AfterValidator(_disk)]
    mac_addr: str = Field(pattern=r"^([0-9a-f]{2}:){5}[0-9a-f]{2}$")
    # Falls back to talos.schematic_id when unset.
    schematic_id: OptionalSchematicId = None
    mtu: int = Field(default=1500, ge=1450, le=9000)
    secureboot: bool = False
    encrypt_disk: bool = False
    kernel_modules: list[str] = []

    @model_validator(mode="after")
    def check(self) -> Self:
        if self.name in ("global", "controller", "worker"):
            raise ValueError(f"node name {self.name!r} is reserved")
        return self


class Config(Model):
    model_config = ConfigDict(extra="forbid", title="cluster.toml")

    network: Network
    kubernetes: Kubernetes
    gateways: Gateways
    repository: Repository
    domain: Domain
    dns: Dns
    # Defaults to "cloudflare-tunnel" when dns.provider is "cloudflare",
    # otherwise "none".
    ingress: Ingress = Field(
        default_factory=lambda data: Ingress(
            mode="cloudflare-tunnel" if data["dns"].provider == "cloudflare" else "none"
        )
    )
    cilium: Cilium = Cilium()
    talos: Talos = Talos()
    spegel: Spegel = Spegel()
    nodes: list[Node]

    @computed_field
    @property
    def cilium_bgp_enabled(self) -> bool:
        return self.cilium.announce == "bgp"

    # The gateways that are deployed, by name: envoy-external only exists
    # when ingress.mode is not "none".
    @property
    def deployed_gateways(self) -> dict[str, Gateway]:
        gateways = {"internal": self.gateways.internal, "dns": self.gateways.dns}
        if self.ingress.mode != "none" and self.gateways.external is not None:
            gateways["external"] = self.gateways.external
        return gateways

    # Their LB IPAM addresses keyed by cluster.toml path; gateways using a
    # load_balancer_class get theirs from that implementation instead.
    @property
    def gateway_ips(self) -> dict[str, IPv4Address]:
        return {
            f"gateways.{name}": gateway.address
            for name, gateway in self.deployed_gateways.items()
            if gateway.address is not None
        }

    @computed_field
    @property
    def gateway_addresses(self) -> list[str]:
        return [str(addr) for addr in self.gateway_ips.values()]

    @computed_field
    @property
    def cilium_node_ipam_enabled(self) -> bool:
        return any(
            gateway.load_balancer_class == "io.cilium/node"
            for gateway in self.deployed_gateways.values()
        )

    # networks.yaml holds the LB IPAM pool and the L2 or BGP announcements.
    @computed_field
    @property
    def cilium_networks_needed(self) -> bool:
        return bool(self.gateway_ips) or self.cilium.announce != "none"

    # Replica counts for control-plane-only workloads key off this rather
    # than len(nodes); a cluster can have many workers but one controller.
    @computed_field
    @property
    def controller_count(self) -> int:
        return sum(1 for node in self.nodes if node.controller)

    @computed_field
    @property
    def cluster_issuer(self) -> str:
        if self.dns.provider == "cloudflare":
            return "letsencrypt-production"
        return "internal-ca"

    # Single source for the machine and apiServer certificate SAN lists,
    # which live in separate patch files.
    @computed_field
    @property
    def cert_sans(self) -> list[str]:
        api = self.kubernetes.api
        return list(dict.fromkeys(["127.0.0.1", str(api.addr), *(api.tls_sans or [])]))

    @model_validator(mode="after")
    def check(self) -> Self:
        bgp_configured = self.cilium.bgp.configured
        if self.cilium.announce is None:
            self.cilium.announce = "bgp" if bgp_configured else "l2"
        elif self.cilium.announce == "bgp" and not bgp_configured:
            raise ValueError(
                "cilium.announce 'bgp' requires cilium.bgp router_addr, router_asn and node_asn"
            )
        elif self.cilium.announce != "bgp" and bgp_configured:
            raise ValueError(
                f"cilium.bgp is configured but cilium.announce is {self.cilium.announce!r}"
            )
        if self.spegel.enabled is None:
            self.spegel.enabled = len(self.nodes) > 1
        # None means unset; the string "none" disables the webhook. A hosted
        # Git provider cannot reach an internal-only route, so those opt in.
        if self.repository.webhook_provider is None:
            self.repository.webhook_provider = "none" if self.ingress.mode == "none" else "github"
        for i, node in enumerate(self.nodes):
            if node.schematic_id is None:
                node.schematic_id = self.talos.schematic_id
            if node.schematic_id is None:
                raise ValueError(
                    f"nodes[{i}].schematic_id is required: set it on the node "
                    "or set a cluster-wide default in [talos]"
                )
        if self.controller_count == 0:
            raise ValueError("at least one node must have controller = true")
        if self.ingress.mode != "none" and self.dns.provider != "cloudflare":
            raise ValueError(
                f"ingress.mode {self.ingress.mode!r} requires dns.provider 'cloudflare'"
            )
        if self.ingress.mode != "none" and self.gateways.external is None:
            raise ValueError(
                f"gateways.external is required when ingress.mode is {self.ingress.mode!r}"
            )

        cidrs = {
            "network.node_cidr": self.network.node_cidr,
            "kubernetes.pod_cidr": self.kubernetes.pod_cidr,
            "kubernetes.svc_cidr": self.kubernetes.svc_cidr,
        }
        names = list(cidrs)
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                if cidrs[a].overlaps(cidrs[b]):
                    raise ValueError(f"{a} {cidrs[a]} overlaps {b} {cidrs[b]}")

        api = self.kubernetes.api
        if not api.vip:
            controllers = [n.address for n in self.nodes if n.controller]
            if controllers != [api.addr]:
                raise ValueError(
                    "kubernetes.api.vip = false requires exactly one controller with "
                    "kubernetes.api.addr set to its address (controllers: "
                    f"{', '.join(map(str, controllers))})"
                )
        elif any(n.address == api.addr for n in self.nodes):
            raise ValueError(
                f"kubernetes.api.addr {api.addr} is a node address: use an unused IP for "
                "the API VIP, or set kubernetes.api.vip = false to serve the API on the "
                "controller of a single-controller cluster"
            )
        # Both Envoy Services would bind :80 and :443 on the same node IPs.
        node_ipam = [
            f"gateways.{name}"
            for name, gateway in self.deployed_gateways.items()
            if name != "dns" and gateway.load_balancer_class == "io.cilium/node"
        ]
        if len(node_ipam) > 1:
            raise ValueError(
                f"{' and '.join(node_ipam)} both use load_balancer_class 'io.cilium/node' "
                "and would listen on the same node ports; use it for one of them only"
            )

        gateways = self.gateway_ips
        addresses = (
            gateways
            | {"network.default_gateway": self.network.default_gateway}
            | {f"nodes[{i}].address": n.address for i, n in enumerate(self.nodes)}
        )
        if api.vip:
            addresses["kubernetes.api.addr"] = api.addr
        seen: dict[IPv4Address, str] = {}
        for owner, addr in addresses.items():
            if addr in seen:
                raise ValueError(f"address {addr} is used by both {seen[addr]} and {owner}")
            seen[addr] = owner
        # The BGP peer is commonly the LAN router, i.e. the default gateway.
        routed = dict(gateways)
        if self.cilium_bgp_enabled:
            router = self.cilium.bgp.router_addr
            if seen.get(router, "network.default_gateway") != "network.default_gateway":
                raise ValueError(
                    f"address {router} is used by both {seen[router]} and cilium.bgp.router_addr"
                )
            addresses["cilium.bgp.router_addr"] = router
            routed["cilium.bgp.router_addr"] = router

        node_cidr = self.network.node_cidr
        # /31 and /32 have no network or broadcast address (RFC 3021).
        if node_cidr.prefixlen < 31:
            unusable = {node_cidr.network_address, node_cidr.broadcast_address}
            for owner, addr in addresses.items():
                if addr in unusable:
                    raise ValueError(
                        f"{owner} {addr} is the network or broadcast address of node_cidr {node_cidr}"
                    )

        # Gateway addresses (unless announced over L2) and the BGP peer may
        # leave node_cidr, but never into the in-cluster ranges, where they
        # would shadow pod or Service IPs, nor into addresses no network
        # routes.
        for owner, addr in routed.items():
            if (
                addr.is_unspecified
                or addr.is_loopback
                or addr.is_link_local
                or addr.is_multicast
                or addr.is_reserved
            ):
                raise ValueError(
                    f"{owner} {addr} is not routable "
                    "(unspecified, loopback, link-local, multicast or reserved)"
                )
            for cidr_name in ("pod_cidr", "svc_cidr"):
                cidr = getattr(self.kubernetes, cidr_name)
                if addr in cidr:
                    raise ValueError(f"{owner} {addr} is inside kubernetes.{cidr_name} {cidr}")

        for i, node in enumerate(self.nodes):
            if node.address not in node_cidr:
                raise ValueError(
                    f"nodes[{i}].address {node.address} is not inside node_cidr {node_cidr}"
                )
        if self.kubernetes.api.addr not in node_cidr:
            raise ValueError(
                f"kubernetes.api.addr {self.kubernetes.api.addr} is not inside node_cidr {node_cidr}"
            )
        # Over L2 only addresses in the node network can be announced.
        if self.cilium.announce == "l2":
            for owner, addr in gateways.items():
                if addr not in node_cidr:
                    raise ValueError(
                        f"{owner} {addr} is not inside node_cidr {node_cidr} "
                        "(required when cilium.announce is 'l2')"
                    )

        for field, label in (("name", "name"), ("mac_addr", "MAC address")):
            values: dict[str, int] = {}
            for i, node in enumerate(self.nodes):
                value = getattr(node, field)
                if value in values:
                    raise ValueError(
                        f"duplicate node {label} {value!r} on nodes[{values[value]}] and nodes[{i}]"
                    )
                values[value] = i
        return self


def format_errors(error: ValidationError) -> str:
    lines = []
    for err in error.errors():
        # Reported alongside the real error whenever a field a default
        # factory depends on failed; it carries no information of its own.
        if err["type"] == "default_factory_not_called":
            continue
        loc = ".".join(str(part) for part in err["loc"])
        msg = err["msg"].removeprefix("Value error, ")
        lines.append(f"{loc}: {msg}" if loc else msg)
    return "\n".join(lines)


class ConfigError(Exception):
    pass


# Validate config_file and return the defaulted config as a plain dict.
# Raises ConfigError with a human-readable message.
def load(config_file: str = "cluster.toml") -> dict[str, Any]:
    path = Path(config_file)
    try:
        raw = tomllib.loads(path.read_text())
    except FileNotFoundError:
        raise ConfigError(f"{path}: file not found") from None
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"{path}: invalid TOML: {e}") from None

    try:
        config = Config.model_validate(raw)
    except ValidationError as e:
        raise ConfigError(format_errors(e)) from None

    # Unset optionals stay in the dump as None rather than being dropped:
    # makejinja renders with StrictUndefined, so a template testing
    # network.vlan_tag needs the key to exist.
    return config.model_dump(mode="json")


# JSON Schema for editor completion and validation of cluster.toml (taplo's
# #:schema directive). Cross-field rules and data-aware defaults only exist in
# the model validators, so the schema is an editing aid, not the gate.
def schema() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        **Config.model_json_schema(),
    }


def main() -> int:
    if sys.argv[1:] == ["--schema"]:
        json.dump(schema(), sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    try:
        data = load(sys.argv[1] if len(sys.argv) > 1 else "cluster.toml")
    except ConfigError as e:
        print(e, file=sys.stderr)
        return 1
    json.dump(data, sys.stdout, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
