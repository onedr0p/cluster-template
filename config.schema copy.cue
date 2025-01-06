package config

import (
	"net"
	"list"
)

#Config: {
	cluster:     #Cluster
	flux:        #Flux
	cloudflare?: #Cloudflare
}

#Cluster: {
	nodes: #Nodes
	network: #Network & {
		podCidr:     !=nodes.network
		serviceCidr: !=nodes.network
	}
	api: #API
}

#Nodes: {
	schematicId:     =~"^[a-z0-9]{64}$"
	network:         net.IPCIDR
	defaultGateway?: net.IPv4 | ""
	inventory: [...#NodeInventory]
	_inventoryCheck: {
		controller: mod(len([for item in inventory if !item.controller {item.name}]), 2) != 0 & false
		name: list.UniqueItems() & [for item in inventory {item.name}]
		address: list.UniqueItems() & [for item in inventory {item.address}]
		macAddr: list.UniqueItems() & [for item in inventory {item.macAddr}]
	}
	dns: [...net.IPv4]
}

#NodeInventory: {
	name:         =~"^[a-z0-9][a-z0-9\\-]{0,61}[a-z0-9]$|^[a-z0-9]$" & !="global" & !="controller" & !="worker"
	address:      net.IPv4
	controller:   bool
	disk:         string
	macAddr:      =~"^([0-9a-f]{2}[:]){5}([0-9a-f]{2})$"
	schematicId?: string & =~"^[a-z0-9]{64}$" | ""
}

#Network: {
	podCidr:           net.IPCIDR & !=serviceCidr
	serviceCidr:       net.IPCIDR & !=podCidr
}

#API: {
	address: net.IPv4
	sans?: [...net.FQDN]
}

#Flux: {
	github: #GitHub
	sops:   #Sops
}

#GitHub: {
	address:     =~"^(https://|ssh://git@)github\\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\\.git$"
	branch:      string
	token?:      string & =~"^[a-z0-9]{32}$" | ""
	privateKey?: string & =~"^-----BEGIN OPENSSH PRIVATE KEY-----" | ""
}

#Sops: publicKey: =~"^age1[a-z0-9]{58}$"

#Cloudflare: {
	enabled: bool
	domain:  net.FQDN
	token:   string
	acme:    #Acme
	ingress: #Ingress
	dns:     #DNS
	tunnel:  #Tunnel
}

#Acme: {
	email:      string
	production: bool
}

#Ingress: address: net.IPv4

#DNS: address: net.IPv4

#Tunnel: {
	id:        string
	accountId: string
	secret:    string
	ingress:   #TunnelIngress
}

#TunnelIngress: address: net.IPv4

#Config
