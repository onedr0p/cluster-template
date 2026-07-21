package config

import (
	"net"
	"list"
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

	// Pairwise CIDR uniqueness. We can't use list.UniqueItems on these because
	// kubernetes.pod_cidr/svc_cidr are defaulted disjunctions (`*"…" | net.IPCIDR`),
	// and CUE evaluates the list constraint against the unresolved disjunction —
	// so the defaulted values silently slip through. Pairwise `!=` works.
	network: node_cidr: !=kubernetes.pod_cidr & !=kubernetes.svc_cidr
	kubernetes: pod_cidr: !=network.node_cidr & !=kubernetes.svc_cidr
	kubernetes: svc_cidr: !=network.node_cidr & !=kubernetes.pod_cidr

	_addrs_check: list.UniqueItems() & [
		kubernetes.api.addr, gateways.internal, gateways.dns, gateways.external,
	]

	_node_name_check: list.UniqueItems() & [for n in nodes {n.name}]
	_node_addr_check: list.UniqueItems() & [for n in nodes {n.address}]
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
	default_gateway?: net.IPv4 & !=""
	// VLAN tag for the Talos nodes (rare).
	vlan_tag?: string & !=""
}

#Kubernetes: {
	// The pod CIDR for the cluster, /16 recommended.
	pod_cidr: *"10.42.0.0/16" | net.IPCIDR
	// The service CIDR for the cluster, /16 recommended.
	svc_cidr: *"10.43.0.0/16" | net.IPCIDR
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
	// emulate GitHub webhooks, so "github" also covers them.
	webhook_provider: *"github" | "gitlab" | "generic-hmac"
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
		// The BGP router ASN.
		router_asn: *"" | string & !=""
		// The BGP node ASN.
		node_asn: *"" | string & !=""
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
