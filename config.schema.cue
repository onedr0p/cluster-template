package config

import (
	"net"
	"list"
)

#Config: {
	cluster:           #Cluster
	gitops:            #GitOps
}

#Cluster: {
	api: {
		address: net.IPv4
		sans?: [...net.FQDN]
	}
	network: {
		dns_servers?: [...net.IPv4]
		node_cidr: net.IPCIDR & !=service_cidr & !=pod_cidr
		ntp_servers?: [...net.IPv4]
		pod_cidr:     net.IPCIDR & !=service_cidr & !=node_cidr
		service_cidr: net.IPCIDR & !=pod_cidr & !=node_cidr
	}
	nodes: [...#Node]
	_nodesCheck: {
		controller: mod(len([for item in nodes if !item.controller {item.name}]), 2) != 0 & false
		name: list.UniqueItems() & [for item in nodes {item.name}]
		address: list.UniqueItems() & [for item in nodes {item.address}]
		macAddr: list.UniqueItems() & [for item in nodes {item.mac_addr}]
	}
}

#Node: {
	address:      net.IPv4
	controller:   bool
	disk:         string
	mac_addr:     =~"^([0-9a-f]{2}[:]){5}([0-9a-f]{2})$"
	name:         =~"^[a-z0-9][a-z0-9\\-]{0,61}[a-z0-9]$|^[a-z0-9]$" & !="global" & !="controller" & !="worker"
	schematic_id: string & =~"^[a-z0-9]{64}$"
}

#GitOps: {
	enabled: bool
	encryption: age: public_key: =~"^age1[a-z0-9]{58}$"
	external_services: {
		enabled: bool
		dns: address: net.IPv4
		ingress: address: net.IPv4
		cloudflare: {
			enabled: bool
			domain:  net.FQDN
			token:   string
			acme: {
				email:      string
				production: bool
			}
			tunnel: {
				id:         string
				account_id: string
				secret:     string
				ingress: address: net.IPv4
			}
		}
	}
	repository: {
		url:    =~"^(https://|ssh://git@)github\\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\\.git$"
		branch: string
		auth: {
			token:    string & =~"^[a-z0-9]{32}$"
			ssh_key?: string & =~"^-----BEGIN OPENSSH PRIVATE KEY-----"
		}
	}
}

#Config
