terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "3.28.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "0.7.1"
    }
  }
}

data "sops_file" "settings" {
    source_file = "secret.sops.yaml"
}

provider "cloudflare" {
    email = data.sops_file.settings.data["cloudflare_email"]
    api_key = data.sops_file.settings.data["cloudflare_token"]
}

data "cloudflare_zones" "domain" {
  filter {
    name = data.sops_file.settings.data["cloudflare_domain"]
  }
}

resource "cloudflare_record" "tunnel_route" {
  name    = data.sops_file.settings.data["tunnel_route"]
  zone_id = lookup(data.cloudflare_zones.domain.zones[0], "id")
  value   = "${data.sops_file.settings.data["tunnel_id"]}.cfargotunnel.com"
  proxied = true
  type    = "CNAME"
  ttl     = 1
}
