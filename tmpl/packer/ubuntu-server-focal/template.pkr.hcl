# Ubuntu Server Focal
# ---
# Packer Template to create an Ubuntu Server (Focal) on Proxmox

# Variable Definitions
variable "proxmox_api_url" {
    type = string
}

variable "proxmox_api_token_id" {
    type = string
}

variable "proxmox_api_token_secret" {
    type = string
    sensitive = true
}

variable "proxmox_build_os"{
    type = string
}

variable "proxmox_node"{
    type = string
}

variable "proxmox_vm_id"{
    type = string
}

variable "proxmox_vm_desc"{
    type = string
}

variable "proxmox_iso_file"{
    type = string
}

variable "proxmox_iso_file"{
    type = string
}

variable "proxmox_iso_storage_pool"{
    type = string
}

variable "proxmox_cores"{
    type = string
}

variable "proxmox_memory"{
    type = string
}

variable "proxmox_host_bind_address"{
    type = string
}

variable "proxmox_ssh_username"{
    type = string
}

variable "proxmox_ssh_private_key"{
    type = string
}
# Resource Definiation for the VM Template
source "proxmox" "ubuntu-server-focal" {
 
    # Proxmox Connection Settings
    proxmox_url = "${var.proxmox_api_url}"
    username = "${var.proxmox_api_token_id}"
    token = "${var.proxmox_api_token_secret}"
    # (Optional) Skip TLS Verification
    insecure_skip_tls_verify = true
    
    # VM General Settings
    node = "${var.proxmox_node}"
    vm_id = "${var.proxmox_vm_id}"
    vm_name = "${var.proxmox_vm_name}"
    template_description = "${var.proxmox_desc}"

    # VM OS Settings
    # (Option 1) Local ISO File
    iso_file = "${var.proxmox_iso_file}"
    # - or -
    # (Option 2) Download ISO
    # iso_url = "https://releases.ubuntu.com/20.04/ubuntu-20.04.4-live-server-amd64.iso"
    # iso_checksum = "28ccdb56450e643bad03bb7bcf7507ce3d8d90e8bf09e38f6bd9ac298a98eaad"
    iso_storage_pool = "${var.proxmox_iso_storage_pool}"
    unmount_iso = true

    # VM System Settings
    qemu_agent = true

    # VM Hard Disk Settings
    scsi_controller = "virtio-scsi-pci"

    disks {
        disk_size = "20G"
        format = "qcow2"
        storage_pool = "local-lvm"
        storage_pool_type = "lvm"
        type = "sata"
    }

    # VM CPU Settings
    cores = "${var.proxmox_cores}"
    
    # VM Memory Settings
    memory = "${var.proxmox_memory}" 

    # VM Network Settings
    network_adapters {
        model = "virtio"
        bridge = "vmbr0"
        firewall = "false"
        # vlan_tag = "30"
    } 

    # VM Cloud-Init Settings
    cloud_init = true
    cloud_init_storage_pool = "local-lvm"

    # PACKER Boot Commands
    boot_command = [
        "<esc><wait><esc><wait>",
        "<f6><wait><esc><wait>",
        "<bs><bs><bs><bs><bs>",
        "autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ",
        "--- <enter>"
    ]
    boot = "c"
    boot_wait = "5s"

    # PACKER Autoinstall Settings
    http_directory = "http" 
    # (Optional) Bind IP Address and Port
    # http_bind_address = "0.0.0.0"
    http_bind_address = "${var.proxmox_http_bind_address}"
    http_port_min = 8802
    http_port_max = 8802

    ssh_username = "${var.proxmox_ssh_username}"

    # (Option 1) Add your Password here
    # ssh_password = "your-password"
    # - or -
    # (Option 2) Add your Private SSH KEY file here
    ssh_private_key_file = "${var.proxmox_ssh_private_key_file}"

    # Raise the timeout, when installation takes longer
    ssh_timeout = "20m"
}

# Build Definition to create the VM Template
build {

    name = "ubuntu-server-focal"
    sources = ["source.proxmox.ubuntu-server-focal"]

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #1
    provisioner "shell" {
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
            "sudo rm /etc/ssh/ssh_host_*",
            "sudo truncate -s 0 /etc/machine-id",
            "sudo apt -y autoremove --purge",
            "sudo apt -y clean",
            "sudo apt -y autoclean",
            "sudo cloud-init clean",
            "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
            "sudo sync"
        ]
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #2
    provisioner "file" {
        source = "files/99-pve.cfg"
        destination = "/tmp/99-pve.cfg"
    }

    # Provisioning the VM Template for Cloud-Init Integration in Proxmox #3
    provisioner "shell" {
        inline = [ "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg" ]
    }

    # Provisioning the VM Template with Teleport
    // provisioner "shell" {
    //     inline = [
    //         "sudo curl https://deb.releases.teleport.dev/teleport-pubkey.asc -o /usr/share/keyrings/teleport-archive-keyring.asc",
    //         "echo \"deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc] https://deb.releases.teleport.dev/ stable main\" | sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null",
    //         "sudo apt-get update",
    //         "sudo apt-get install teleport"
    //     ]
    // }

    # Provisioning the VM Template with OpenTelemetry
    provisioner "shell" {
        inline = [
            "sudo apt-get -y install wget systemctl",
            "wget https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v0.51.0/otelcol_0.51.0_linux_amd64.deb",
            "sudo dpkg -i otelcol_0.51.0_linux_amd64.deb",
        ]
    }

    # Provisioning the VM Template with Falco
    provisioner "shell" {
        inline = [
            "sudo curl -s https://falco.org/repo/falcosecurity-3672BA8F.asc | apt-key add -",
            "echo \"deb https://download.falco.org/packages/deb stable main\" | tee -a /etc/apt/sources.list.d/falcosecurity.list",
            "apt-get update -y",
            "apt-get -y install linux-headers-$(uname -r)",
            "apt-get install -y falco"
        ]
    }
}
