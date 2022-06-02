packer {
  required_plugins {
    proxmox = {
      version = ">= 1.0.7"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}
