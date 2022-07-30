terraform {

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "3.20.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "2.2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "0.7.1"
    }
  }
}

data "sops_file" "cloudflare_secrets" {
  source_file = "secret.sops.yaml"
}

provider "cloudflare" {
  email   = data.sops_file.cloudflare_secrets.data["cloudflare_email"]
  api_key = data.sops_file.cloudflare_secrets.data["cloudflare_apikey"]
}

data "cloudflare_zones" "domain" {
  filter {
    name = data.sops_file.cloudflare_secrets.data["cloudflare_domain"]
  }
}

resource "cloudflare_zone_settings_override" "cloudflare_settings" {
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  settings {
    # /ssl-tls
    ssl = "strict"
    # /ssl-tls/edge-certificates
    always_use_https         = "on"
    min_tls_version          = "1.2"
    opportunistic_encryption = "on"
    tls_1_3                  = "zrt"
    automatic_https_rewrites = "on"
    universal_ssl            = "on"
    # /firewall/settings
    browser_check  = "on"
    challenge_ttl  = 1800
    privacy_pass   = "on"
    security_level = "medium"
    # /speed/optimization
    brotli = "on"
    minify {
      css  = "on"
      js   = "on"
      html = "on"
    }
    rocket_loader = "on"
    # /caching/configuration
    always_online    = "off"
    development_mode = "off"
    # /network
    http3               = "on"
    zero_rtt            = "on"
    ipv6                = "on"
    websockets          = "on"
    opportunistic_onion = "on"
    pseudo_ipv4         = "off"
    ip_geolocation      = "on"
    # /content-protection
    email_obfuscation   = "on"
    server_side_exclude = "on"
    hotlink_protection  = "off"
    # /workers
    security_header {
      enabled = false
    }
  }
}

data "http" "ipv4" {
  url = "http://ipv4.icanhazip.com"
}

resource "cloudflare_record" "ipv4" {
  name    = "ipv4"
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = chomp(data.http.ipv4.response_body)
  proxied = true
  type    = "A"
  ttl     = 1
}

resource "cloudflare_record" "root" {
  name    = data.sops_file.cloudflare_secrets.data["cloudflare_domain"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "ipv4.${data.sops_file.cloudflare_secrets.data["cloudflare_domain"]}"
  proxied = true
  type    = "CNAME"
  ttl     = 1
}
