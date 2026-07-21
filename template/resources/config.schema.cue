package config

import (
	"net"
	"list"
	"strconv"
	"strings"
)

#Config: {
	network:    #Network
	kubernetes: #Kubernetes
	gateways:   #Gateways
	repository: #Repository
	cloudflare: #Cloudflare
	cilium:     #Cilium
	nodes: [...#Node]

	spegel_enabled:     bool | *(len(nodes) > 1)
	cilium_bgp_enabled: cilium.bgp.router_addr != "" && cilium.bgp.router_asn != "" && cilium.bgp.node_asn != ""

	let _node_base = strings.Split(network.node_cidr, "/")[0]
	let _pod_base = strings.Split(kubernetes.pod_cidr, "/")[0]
	let _svc_base = strings.Split(kubernetes.svc_cidr, "/")[0]

	// CIDRs must be written in network-address form (no host bits set), since
	// derived addresses offset from the base IP. A canonical base minus one
	// lands outside the CIDR; a base with host bits set does not.
	_cidr_canonical_check: {
		node_cidr_has_host_bits: false & net.InCIDR(net.AddIP(_node_base, -1), network.node_cidr)
		pod_cidr_has_host_bits:  false & net.InCIDR(net.AddIP(_pod_base, -1), kubernetes.pod_cidr)
		svc_cidr_has_host_bits:  false & net.InCIDR(net.AddIP(_svc_base, -1), kubernetes.svc_cidr)
	}

	// The node, pod and service CIDRs must not overlap. Checking containment
	// of each network address catches nested ranges, not just equal strings.
	_cidr_overlap_check: {
		node_cidr_overlaps_pod_cidr: false & (net.InCIDR(_node_base, kubernetes.pod_cidr) || net.InCIDR(_pod_base, network.node_cidr))
		node_cidr_overlaps_svc_cidr: false & (net.InCIDR(_node_base, kubernetes.svc_cidr) || net.InCIDR(_svc_base, network.node_cidr))
		pod_cidr_overlaps_svc_cidr:  false & (net.InCIDR(_pod_base, kubernetes.svc_cidr) || net.InCIDR(_svc_base, kubernetes.pod_cidr))
	}

	// The API VIP, gateway VIPs, default gateway and node addresses must all
	// be distinct.
	_addr_uniqueness_check: list.UniqueItems() & [
		kubernetes.api.addr, gateways.internal, gateways.dns, gateways.external, network.default_gateway,
		for n in nodes {n.address},
	]

	// Node addresses, the API VIP and the default gateway live in the node
	// network; the CoreDNS address lives in the service network.
	_node_addrs_in_node_cidr: [for n in nodes {true & net.InCIDR(n.address, network.node_cidr)}]
	_api_addr_in_node_cidr:        true & net.InCIDR(kubernetes.api.addr, network.node_cidr)
	_default_gateway_in_node_cidr: true & net.InCIDR(network.default_gateway, network.node_cidr)
	_coredns_addr_in_svc_cidr:     true & net.InCIDR(kubernetes.coredns_addr, kubernetes.svc_cidr)

	// Without BGP the gateway VIPs are announced over L2 and must also live
	// in the node network.
	if !cilium_bgp_enabled {
		_gateways_in_node_cidr: [for g in [gateways.internal, gateways.dns, gateways.external] {true & net.InCIDR(g, network.node_cidr)}]
	}

	_node_name_check: list.UniqueItems() & [for n in nodes {n.name}]
	_node_mac_check:  list.UniqueItems() & [for n in nodes {n.mac_addr}]

	network: dns_servers: *["1.1.1.1", "1.0.0.1"] | _
	network: ntp_servers: *["162.159.200.1", "162.159.200.123"] | _
}

#Network: {
	// The network CIDR for the nodes.
	// e.g. "192.168.1.0/24"
	node_cidr: net.IPCIDR
	// DNS servers to use for the cluster (default: ["1.1.1.1", "1.0.0.1"]).
	dns_servers: [...net.IPv4]
	// NTP servers to use for the cluster (default: ["162.159.200.1", "162.159.200.123"]).
	ntp_servers: [...net.IPv4]
	// The default gateway for the nodes (defaults to the first IP in node_cidr).
	default_gateway: net.IPv4 & !="" | *net.AddIP(strings.Split(node_cidr, "/")[0], 1)
	// VLAN tag for the Talos nodes (rare). Must be 1-4094.
	vlan_tag?: =~"^[0-9]+$"
	if vlan_tag != _|_ {
		_vlan_tag_in_range: strconv.Atoi(vlan_tag) & >=1 & <=4094
	}
}

#Kubernetes: {
	// The pod CIDR for the cluster, /16 recommended.
	pod_cidr: *"10.42.0.0/16" | net.IPCIDR
	// The service CIDR for the cluster, /16 recommended.
	svc_cidr: *"10.43.0.0/16" | net.IPCIDR
	// IP handed to the CoreDNS Service (defaults to the 10th IP in svc_cidr).
	coredns_addr: net.IPv4 & !="" | *net.AddIP(strings.Split(svc_cidr, "/")[0], 10)
	api: {
		// The IP address of the Kube API.
		addr: net.IPv4
		// Additional SANs to add to the Kube API cert.
		tls_sans?: [...net.FQDN]
	}
}

#Gateways: {
	// Internal gateway load balancer IP.
	internal: net.IPv4
	// k8s_gateway DNS load balancer IP.
	dns: net.IPv4
	// External (cloudflared) gateway load balancer IP.
	external: net.IPv4
}

// Git hosts whose SSH host keys are bundled with the template; ssh:// URLs
// pointing anywhere else must provide repository.known_hosts.
_known_ssh_hosts: ["github.com", "gitlab.com", "codeberg.org"]

#Repository: {
	// Full clone URL Flux will sync from. Use https:// for a publicly
	// readable repository, or ssh://git@… for one that needs the deploy key.
	// e.g. "https://github.com/onedr0p/home-ops.git"
	//      "ssh://git@gitlab.com/owner/home-ops.git"
	//      "ssh://git@git.example.com/owner/home-ops.git"
	url: =~"^(https://|ssh://git@)[^/]+/.+$"
	// Repository branch Flux watches.
	branch: *"main" | string & !=""
	// Webhook payload format the Flux Receiver verifies. Gitea and Forgejo
	// emulate GitHub webhooks, so "github" also covers them. Set to "none"
	// to skip the webhook entirely; Flux then only polls on an interval.
	webhook_provider: *"github" | "gitlab" | "generic-hmac" | "none"
	// SSH host keys for the git host (ssh-keyscan output). Bundled for
	// github.com, gitlab.com and codeberg.org; required for ssh:// URLs to
	// any other host.
	known_hosts: *"" | string

	_ssh:  strings.HasPrefix(url, "ssh://")
	_host: strings.Split(strings.Split(strings.TrimPrefix(url, "ssh://git@"), "/")[0], ":")[0]
	if _ssh && !list.Contains(_known_ssh_hosts, _host) {
		known_hosts: string & !=""
	}
}

#Cloudflare: {
	// Domain you wish to use from your Cloudflare account.
	domain: net.FQDN
	// API token with Zone:DNS:Edit and Account:Cloudflare Tunnel:Read permissions.
	token: string
}

#Cilium: {
	// The load balancer mode for cilium.
	loadbalancer_mode: *"dsr" | "snat"
	bgp: {
		// The IP address of the BGP router.
		router_addr: *"" | net.IPv4 & !=""
		// The BGP router ASN (1-4294967295).
		router_asn: *"" | =~"^[0-9]+$"
		// The BGP node ASN (1-4294967295).
		node_asn: *"" | =~"^[0-9]+$"
		_asn_range_check: {
			for name, value in {router: router_asn, node: node_asn} if value != "" {
				(name): strconv.Atoi(value) & >=1 & <=4294967295
			}
		}
	}
}

#Node: {
	// Name of the node (must match [a-z0-9-]+).
	name: =~"^[a-z0-9][a-z0-9\\-]{0,61}[a-z0-9]$|^[a-z0-9]$" & !="global" & !="controller" & !="worker"
	// IP address of the node (must be in network.node_cidr).
	address: net.IPv4
	// Set to true if this is a controller node.
	controller: bool
	// Device path or serial number of the disk.
	disk: string
	// MAC address of the NIC.
	mac_addr: =~"^([0-9a-f]{2}[:]){5}([0-9a-f]{2})$"
	// Schematic ID from https://factory.talos.dev/.
	schematic_id: =~"^[a-z0-9]{64}$"
	// MTU for the NIC.
	mtu?: >=1450 & <=9000
	// SecureBoot mode.
	secureboot?: bool
	// TPM-based disk encryption.
	encrypt_disk?: bool
	// Kernel modules required by schematic_id extensions.
	kernel_modules?: [...string]
}

#Config
