package config

import "net"

#Config: {
    cluster: #Cluster
    flux: #Flux
    cloudflare?: #Cloudflare
}

#Cluster: {
    name: string & !=""
    sops: #Sops
    nodes: #Nodes
    network: #Network
    api: #API
}

#Sops: {
    publicKey: string & !=""
}

#Nodes: {
    schematicId: string & =~"^([a-z0-9]{64})$"
    network: net.IPCIDR & !=""
    defaultGateway?: net.IPv4 & !=""
    inventory: [...#NodeInventory]
    vlan?: int & >=1 & <=4094
    dns: [...net.IPv4]
    ntp: [...net.IPv4]
}

#NodeInventory: {
    name: string & =~"^([a-z0-9-]{0,32})$"
    address: net.IPv4 & !=""
    controller: bool
    disk: string & !=""
    macAddr: string & =~"^([0-9a-f]{2}[:]){5}([0-9a-f]{2})$"
    mtu?: int & >=1300 & <=9216
    schematicId?: string & =~"^([a-z0-9]{64})$"
}

#Network: {
    podCidr: net.IPCIDR & !="" & !=serviceCidr & !=#Nodes.network
    serviceCidr: net.IPCIDR & !="" & !=podCidr & !=#Nodes.network
    loadBalancerMode?: "snat" | "dsr"
}

#API: {
    address: net.IPv4 & !=""
    sans?: [...net.FQDN]
}

#Flux: {
    github: #GitHub
}

#GitHub: {
    address: string & !=""
    branch: string & !=""
    token?: string & =~"^([a-z0-9]{32})$"
    privateKey?: string & =~ """
        ^-----BEGIN OPENSSH PRIVATE KEY-----
        ([A-Za-z0-9+/=]{1,76}\\n)*[A-Za-z0-9+/=]{1,76}
        -----END OPENSSH PRIVATE KEY-----$
    """,
}

#Cloudflare: {
    enabled: bool
    domain: net.FQDN & !=""
    token: string & !=""
    acme: #Acme
    ingress: #Ingress
    dns: #DNS
    tunnel: #Tunnel
}

#Acme: {
    email: string & !=""
    production: bool
}

#Ingress: {
    address: net.IPv4 & !=""
}

#DNS: {
    address: net.IPv4 & !=""
}

#Tunnel: {
    id: string & !=""
    accountId: string & !=""
    secret: string & !=""
    ingress: #TunnelIngress
}

#TunnelIngress: {
    address: net.IPv4 & !=""
}
