# Deploy a Kubernetes cluster backed by Flux

Welcome to my highly opinionated template for deploying a single Kubernetes ([k3s](https://k3s.io)) cluster with [Ansible](https://www.ansible.com) and using [Flux](https://toolkit.fluxcd.io) to manage its state.

## Table of contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Machine preparation](#machine-preparation)
- [Getting started](#getting-started)
- [Usage: GitOps with Flux, Renovate and GitHub Actions](#usage-gitops-with-flux-renovate-and-github-actions)
- [What's next](#whats-next)
- [Troubleshooting](#troubleshooting)
- [FAQs](#faqs)
- [Support](#support)
- [License](#license)
- [Acknowledgments](#acknowledgments)

## Overview

The goal of this project is to make it easy for people interested in learning Kubernetes to deploy a basic cluster at home and become familiar with the GitOps tool Flux.

This template implements Flux in a way that promotes legibility and ease of use for those who are new (or relatively new) to the technology and GitOps in general. It assumes a typical homelab setup: namely, a single "home prod" cluster running mostly third-party apps.

This project is aimed at homelabbers and self-hosting enthusiasts. [Support](#support) is provided accordingly.

## Features

Features include:

- Automated, reproducible, customizable setup through Ansible templates and playbooks
- Opinionated implementation of Flux with [strong community support](https://github.com/onedr0p/flux-cluster-template#-support)
- Encrypted secrets thanks to [SOPS](https://github.com/getsops/sops) and [Age](https://github.com/FiloSottile/age)
- Web application firewall thanks to [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)
- SSL certificates thanks to [Cloudflare](https://cloudflare.com) and [cert-manager](https://cert-manager.io)
- HA control plane capability thanks to [kube-vip](https://kube-vip.io)
- Next-gen networking thanks to [Cilium](https://cilium.io/)
- A [Renovate](https://www.mend.io/renovate)-ready repository
- Integrated [GitHub Actions](https://github.com/features/actions)

... and more!

## Prerequisites

### General

You must:

- Bring a **positive attitude** and be ready to learn from failures.
- Run the cluster on bare metal machines or VMs within your home network &mdash; **this is NOT designed for cloud environments**.
- Be willing to commit encrypted secrets to a public GitHub repository.
- Give your nodes unrestricted internet access; air-gapped environments won't work.

### Infrastructure

You will need:

- A [Cloudflare](https://cloudflare.com) account with a domain. You can [register new domains](https://www.cloudflare.com/products/registrar) directly through Cloudflare.
- A DNS server that supports split DNS (eg [Pi-hole](https://pi-hole.net)) **deployed on your home network**.
- Debian 12 freshly installed on 1 or more AMD64/ARM64 bare metal machines or VMs. Each machine will be either a **control node** or a **worker node** in your cluster.
- An **odd number** of control nodes.

## Machine preparation

### System requirements

📍 _k3s default behaviour is that all nodes are able to run workloads, including contol nodes. Worker nodes are therefore optional._

📍 _If you have 3 or more nodes, I recommend making 3 of them control nodes for a highly available control plane._

📍 _Ideally you will run the cluster on bare metal machines. If you intend to run your cluster on Proxmox VE, my thoughts and recommendations about that are documented [here](https://onedr0p.github.io/home-ops/notes/proxmox-considerations.html)._

#### Minimum

| Role      | Memory    | Cores   | Disk        |
|-----------|-----------|---------|-------------|
| Control   | 8GB       | 4       | 100GB SSD   |
| Worker    | 4GB       | 2       | 100GB SSD   |

#### Recommended

| Role      | Memory    | Cores   | System Disk  | Data Disk     | CPU      |
|-----------|-----------|---------|--------------|---------------|----------|
| Any       | 32GB      | 8       | 100GB SSD    | 500GB NVMe    | AMD64    |

### Debian installation instructions for AMD64

1. Download the latest stable release of Debian from [here](https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd), then follow [this guide](https://www.linuxtechi.com/how-to-install-debian-12-step-by-step) to get it installed. Deviations from the guide:

    ```txt
    Choose "Guided - use entire disk"
    Choose "All files in one partition"
    Delete Swap partition
    Uncheck all Debian desktop environment options
    ```

2. [Post install] Remove CD/DVD as apt source

    ```sh
    su -
    sed -i '/deb cdrom/d' /etc/apt/sources.list
    apt update
    exit
    ```

3. [Post install] Enable sudo for your non-root user

    ```sh
    su -
    apt install -y sudo
    usermod -aG sudo ${username}
    echo "${username} ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/${username}
    exit
    newgrp sudo
    sudo apt update
    ```

4. [Post install] Add SSH keys (or use `ssh-copy-id` on the client that is connecting)

    📍 _First make sure your SSH keys are up-to-date and added to your GitHub account [as instructed](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)_

    ```sh
    mkdir -m 700 ~/.ssh
    sudo apt install -y curl
    curl https://github.com/${github_username}.keys > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    ```

### Debian installation instructions for Raspberry Pi 4

📍 _If you choose to use a Raspberry Pi 4 for the cluster, it is recommended to have an 8GB model. Most important is to **boot from an external SSD/NVMe** rather than an SD card. This is supported [natively](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html), however if you have an early model you may need to [update the bootloader](https://www.tomshardware.com/how-to/boot-raspberry-pi-4-usb) first._

1. Download the latest stable release of Debian from [here](https://raspi.debian.net/tested-images). _**Do not** use Raspbian._

2. Flash the image onto an SSD/NVMe drive.

3. Re-mount the drive then do the following (per the [official documentation](https://raspi.debian.net/defaults-and-settings)):

    ```txt
    Open `sysconf.txt` in a text editor
    Change `root_authorized_key` to your desired public SSH key
    Change `root_pw` to your desired root password
    Change `hostname` to your desired hostname
    ```

4. [Post install] Follow steps 3 and 4 from [Debian installation instructions for AMD64](#debian-installation-instructions-for-amd64).

5. [Post install] Install `python3` which is needed by Ansible.

    ```sh
    sudo apt install -y python3
    ```

## Getting started

Once you have installed Debian on your nodes, there are 6 steps to getting a Flux-managed cluster up and runnning.

### 🎉 Step 1: Create a Git repository

1. Create a new **public** repository on GitHub by clicking the big green "Use this template" button at the top of this page.

2. Clone **your new repo** to your local workstation and `cd` into it.

### 🌱 Step 2: Set up your local environment

📍 _Let's get the required tools installed and configured on your local workstation._

1. Install the most recent version of [task](https://taskfile.dev)

    📍 _See the task [installation docs](https://taskfile.dev/installation) for other platforms_

    ```sh
    # Brew
    brew install go-task
    ```

2. Install the most recent version of [direnv](https://direnv.net)

    📍 _See the direnv [installation docs](https://direnv.net/docs/installation.html) for other platforms_

    📍 _After installing `direnv` be sure to [hook it into your shell](https://direnv.net/docs/hook.html) and after that is done run `direnv allow` while in your repo's directory._

    ```sh
    # Brew
    brew install direnv
    ```

3. Setup a Python virual env and install Ansible by running the following task command:

    📍 _This commands requires Python 3.8+ to be installed_

    ```sh
    # Platform agnostic
    task deps
    ```

4. Install the required CLI tools: [age](https://github.com/FiloSottile/age), [flux](https://toolkit.fluxcd.io), [cloudflared](https://github.com/cloudflare/cloudflared), [kubectl](https://kubernetes.io/docs/tasks/tools), [sops](https://github.com/getsops/sops)

   ```sh
   # Brew
   task brew:deps
   ```

### 🔧 Step 3: Do bootstrap configuration

📍 _Both `bootstrap/vars/config.yaml` and `bootstrap/vars/addons.yaml` files contain necessary information that is needed by the bootstrap process._

1. Generate the `bootstrap/vars/config.yaml` and `bootstrap/vars/addons.yaml` configuration files

    ```sh
    task init
    ```

2. Setup your Age private / public key

    📍 _Using [SOPS](https://github.com/getsops/sops) with [Age](https://github.com/FiloSottile/age) allows us to encrypt secrets and use them in Ansible and Flux._

    2a. Create an Age private / public key (this file is gitignored)

      ```sh
      age-keygen -o age.key
      ```

    2b. Fill out the appropriate vars in `bootstrap/vars/config.yaml`

3. Create a Cloudflare API Token

    📍 _To use `cert-manager` with the Cloudflare DNS challenge you will need to create an API Token._

    3a. Log into your Cloudflare dashboard then go [here](https://dash.cloudflare.com/profile/api-tokens). Under the `API Tokens` section, click the blue "Create Token" button.

    3b. Click the blue "Use template" button for the `Edit zone DNS` template.

    3c. Name your token something like `home-kubernetes`

    3d. Under `Permissions`, click `+ Add More` and add each permission below:

    ```text
    Zone - DNS - Edit
    Account - Cloudflare Tunnel - Read
    ```

    3e. Limit the permissions to a specific account and zone resources.

    3f. Fill out the appropriate vars in `bootstrap/vars/config.yaml`

4. Create a Cloudflare Tunnel

    📍 _To expose services to the internet you will need to create a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)._

    4a. Authenticate cloudflared to your domain

      ```sh
      cloudflared tunnel login
      ```

    4b. Create the tunnel

      ```sh
      cloudflared tunnel create k8s
      ```

    4c. In the `~/.cloudflared` directory there will be a json file with details you need. Ignore the `cert.pem` file.

    4d. Fill out the appropriate vars in `bootstrap/vars/config.yaml`

5. Complete filling out the rest of the `bootstrap/vars/config.yaml` configuration file.

    5a. Ensure `bootstrap_acme_production_enabled` is set to `false`.

    5b. [Optional] Update `bootstrap/vars/addons.yaml` and enable applications you would like included.

6. Once done run the following command which will verify and generate all the files needed to continue:

    ```sh
    task configure
    ```

📍 _The configure task will create an `./ansible` directory and the following directories under `./kubernetes`:_

```sh
📁 kubernetes      # Kubernetes cluster defined as code
├─📁 bootstrap     # Flux installation (not tracked by Flux)
├─📁 flux          # Main Flux configuration of repository
└─📁 apps          # Apps deployed into the cluster grouped by namespace
```

### ⚡ Step 4: Prepare your nodes for k3s

📍 _Here we will be running an Ansible playbook to prepare your nodes for running a Kubernetes cluster._

1. Ensure you are able to SSH into your nodes from your workstation using a private SSH key **without a passphrase** (for example [using ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent)). This lets Ansible interact with your nodes.

2. Verify Ansible can view your config

    ```sh
    task ansible:list
    ```

3. Verify Ansible can ping your nodes

    ```sh
    task ansible:ping
    ```

4. Run the Ansible prepare playbook (nodes will reboot when done)

    ```sh
    task ansible:prepare
    ```

### ⛵ Step 5: Use Ansible to install k3s

📍 _Here we will be running an Ansible playbook to install [k3s](https://k3s.io) with [this](https://galaxy.ansible.com/xanmanning/k3s) Ansible galaxy role._

📍 _If you run into problems, you can run `task ansible:nuke` to destroy the k3s cluster and start over from this point._

1. Verify Ansible can view your config

    ```sh
    task ansible:list
    ```

2. Verify Ansible can ping your nodes

    ```sh
    task ansible:ping
    ```

3. Install k3s with Ansible

    ```sh
    task ansible:install
    ```

4. Verify the nodes are online

    📍 _If this command **fails** you likely haven't configured `direnv` as mentioned previously in the guide._

    ```sh
    kubectl get nodes -o wide
    # NAME           STATUS   ROLES                       AGE     VERSION
    # k8s-0          Ready    control-plane,etcd,master   1h      v1.27.3+k3s1
    # k8s-1          Ready    worker                      1h      v1.27.3+k3s1
    ```

5. The `kubeconfig` for interacting with your cluster should have been created in the root of your repository.

### 🚀 Step 6: Install Flux in your cluster

📍 _Here we will be installing [Flux](https://fluxcd.io/flux) after some quick bootstrap steps._

1. Verify Flux can be installed

    ```sh
    flux check --pre
    # ► checking prerequisites
    # ✔ kubectl 1.27.3 >=1.18.0-0
    # ✔ Kubernetes 1.27.3+k3s1 >=1.16.0-0
    # ✔ prerequisites checks passed
    ```

2. Push your changes to GitHub

   📍 _First **verify** that all `*.sops.yaml` and `*.sops.yaml` files under the `./ansible` and `./kubernetes` directories are **encrypted** with SOPS._

    ```sh
    git add -A
    git commit -m "Initial commit :rocket:"
    git push
    ```

3. Install Flux and sync the cluster to your Git repository

   📍 _This command applies `./kubernetes/bootstrap/kustomization.yaml`, which points to the Flux manifests located in the fluxcd/flux2 remote GitHub repo._

    ```sh
    task cluster:install
    # namespace/flux-system configured
    # customresourcedefinition.apiextensions.k8s.io/alerts.notification.toolkit.fluxcd.io created
    # ...
    ```

4. Verify Flux components are running in the cluster

    ```sh
    kubectl -n flux-system get pods -o wide
    # NAME                                       READY   STATUS    RESTARTS   AGE
    # helm-controller-5bbd94c75-89sb4            1/1     Running   0          1h
    # kustomize-controller-7b67b6b77d-nqc67      1/1     Running   0          1h
    # notification-controller-7c46575844-k4bvr   1/1     Running   0          1h
    # source-controller-7d6875bcb4-zqw9f         1/1     Running   0          1h
    ```

### 🎤 Verification steps

_Mic check, 1, 2_ - In a few moments applications should be lighting up like Christmas in July 🎄

1. Output all the common resources in your cluster.

    📍 _Feel free to use the provided [cluster tasks](.taskfiles/ClusterTasks.yaml) for validation of cluster resources or continue to get familiar with the `kubectl` and `flux` CLI tools._

    ```sh
    task cluster:resources
    ```

2. ⚠️ It might take `cert-manager` a while to generate certificates, this is normal so be patient.

3. 🏆 **Congratulations** if all goes smooth you will have a Kubernetes cluster managed by Flux, meaning your Git repository is driving the state of your cluster.

4. 🧠 Now it's time to pause and go get some motel motor oil ☕ and admire you made it this far!

### 🌐 [Post installation] DNS

#### Public DNS

The `external-dns` application created in the `networking` namespace will handle creating public DNS records. By default, `echo-server` and the `flux-webhook` are the only subdomains reachable from the public internet. In order to make additional applications public you must set set the correct ingress class name and ingress annotations like in the HelmRelease for `echo-server`.

#### Home DNS

`k8s_gateway` will provide DNS resolution to external Kubernetes resources (i.e. points of entry to the cluster) from any device that uses your home DNS server. For this to work, your home DNS server must be configured to forward DNS queries for `${bootstrap_cloudflare_domain}` to `${bootstrap_k8s_gateway_addr}` instead of the upstream DNS server(s) it normally uses. This is a form of **split DNS** (aka split-horizon DNS / conditional forwarding).

📍 _Below is how to configure a Pi-hole for split DNS. Other platforms should be similar._

1. Apply this file on the server

   ```sh
   # /etc/dnsmasq.d/99-k8s-gateway-forward.conf
   server=/${bootstrap_cloudflare_domain}/${bootstrap_k8s_gateway_addr}
   ```

2. Restart dnsmasq on the server.

3. Query an internal-only subdomain from your workstation: `dig @${home-dns-server-ip} echo-server.${bootstrap_cloudflare_domain}`. It should resolve to `${bootstrap_internal_nginx_addr}`.

If you're having trouble with DNS be sure to check out these two GitHub discussions: [Internal DNS](https://github.com/onedr0p/flux-cluster-template/discussions/719) and [Pod DNS resolution broken](https://github.com/onedr0p/flux-cluster-template/discussions/635).

### 📜 [Post installation] SSL certificates

By default this template will deploy a wildcard certificate using the Let's Encrypt **staging environment**, which prevents you from getting rate-limited by the Let's Encrypt production servers if your cluster doesn't deploy properly (for example due to a misconfiguration). Once you are sure you will keep the cluster up for more than a few hours be sure to switch to the production servers as outlined in `config.yaml`.

📍 _You will need a production certificate to reach internet-exposed applications through `cloudflared`._

### 🪝 [Post installation] GitHub webhook

By default Flux will check your Git repository for changes every 10 minutes. In order to have Flux reconcile on `git push` you must configure GitHub to send push events.

1. Obtain the webhook path

    📍 _Hook id and path should look like `/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123`_

    ```sh
    kubectl -n flux-system get receiver github-receiver -o jsonpath='{.status.webhookPath}'
    ```

2. Piece together the full URL with the webhook path appended

    ```text
    https://flux-webhook.${bootstrap_cloudflare_domain}/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

3. Navigate to the settings of your repository on GitHub. Under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook URL and your `bootstrap_flux_github_webhook_token` secret and save.

## Usage: GitOps with Flux, Renovate and GitHub Actions

### 🔹 Flux

~

### 🤖 Renovate

[Renovate](https://www.mend.io/renovate) will scan your repository and create PRs for out-of-date dependencies it finds. Merging a PR will cause Flux to apply the change to your cluster.

To enable Renovate, click the 'Configure' button over at their [GitHub App page](https://github.com/apps/renovate) and select your repository. Upon activation, Renovate will create a new issue in your repository, which is a "dashboard" where you can get an overview of the status of all updates. The dashboard has interactive checkboxes that let you do things like advance scheduling or reattempting update PRs you closed without merging.

The base Renovate configuration in your repository can be viewed at [.github/renovate.json5](https://github.com/onedr0p/flux-cluster-template/blob/main/.github/renovate.json5). By default it is scheduled to run on weekends only, but you can [change the schedule to anything you want](https://docs.renovatebot.com/presets-schedule) or simply remove it to let Renovate run around the clock. It is also set up to [automerge some updates](https://github.com/onedr0p/flux-cluster-template/blob/main/.github/renovate/autoMerge.json5).

### ⚙️ GitHub Actions

~

## What's next

The cluster is your oyster (or something like that). Below are some optional considerations you might want to review.

### ➕ Addons

Monitoring tools [Prometheus](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) and [Grafana](https://github.com/grafana/grafana) are recommended if your cluster isn't resource constrained.

Refer to the notes in `bootstrap/vars/addons.yaml` for further advice regarding addons.

### 💾 Storage

The included CSI (`local-path-provisioner`) is a great start for storage but soon you might find you need more features like replicated block storage, or to connect to a NFS/SMB/iSCSI server. If you need any of those features be sure to check out projects like [rook-ceph](https://github.com/rook/rook), [longhorn](https://github.com/longhorn/longhorn), [openebs](https://github.com/openebs/openebs), [democratic-csi](https://github.com/democratic-csi/democratic-csi), [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs), and [synology-csi](https://github.com/SynologyOpenSource/synology-csi).

### 💡 Ship it

To browse or get ideas on applications people are running, community member [@whazor](https://github.com/whazor) created [this website](https://nanne.dev/k8s-at-home-search/) as a creative way to search Flux HelmReleases across GitHub.

## Troubleshooting

Below is a general guide on trying to debug an issue with a resource or application. For example if a workload/resource is not showing up or a pod has started but is stuck in a `CrashLoopBackOff` or `Pending` state.

1. Start by checking all Flux sources and kustomizations and verify they are healthy.

    ```sh
    flux get sources oci -A
    flux get sources git -A
    flux get ks -A
    ```

2. Then check all the Flux HelmReleases and verify they are healthy.

    ```sh
    flux get hr -A
    ```

3. Then check the if the pod is present.

    ```sh
    kubectl -n <namespace> get pods -o wide
    ```

4. Then check the logs of the pod if it's there.

    ```sh
    kubectl -n <namespace> logs <pod-name> -f
    # or
    stern -n <namespace> <fuzzy-name>
    ```

5. If a resource exists, try to describe it to see what problems it might have.

    ```sh
    kubectl -n <namespace> describe <resource> <name>
    ```

6. Check the namespace events

    ```sh
    kubectl get events -n <namespace> --sort-by='.metadata.creationTimestamp'
    ```

Resolving problems could take some tweaking of the YAML manifests in order to get things working. Other times it could be a external factor like NFS permissions or your home network settings. If you are unable to figure out your problem, see the support section below.

## FAQs

### Why Cloudflare Tunnel?

Because of its many advantages:

- Just works™️ no matter which ISP you're with
- Doesn't require you to open ports on your router/firewall
- Enables zero trust access to cluster applications without a VPN

Also because we already use Cloudflare for DNS.

### Are providers other than Cloudflare supported?

No.

### Are operating systems other than Debian supported?

No, and you will likely encounter errors during installation if your nodes run a different operating system.

### Can I add and remove nodes without bringing down my cluster?

Yes, in most cases &mdash; see [this](https://github.com/onedr0p/flux-cluster-template/discussions/589) GitHub discussion.

### I want to change my `config.yaml` or `addons.yaml` and have those changes take effect without bringing down my cluster. Is this possible?

~

### The template iterates quickly. Is it important that I keep up to date with commits?

Not really. If you want to keep up to date, one way is to add the template as a new remote and cherry-pick commits from it as it progresses. The best way is not to worry about every single commit; most important is to branch out from the template and make your cluster **yours**. Don't be afraid to experiment!

### What about new features?

Major updates will be packaged as a new release which you can pull into your repo as you see fit.

## Support

- Make a post in this repository's [GitHub discussions](https://github.com/onedr0p/flux-cluster-template/discussions).
- Start a thread in the `support` or `flux-cluster-template` channel in the [k8s@home](https://discord.gg/k8s-at-home) Discord server.

## License

See [LICENSE](https://github.com/onedr0p/flux-cluster-template/blob/main/LICENSE)

## Acknowledgments

Big shout out to all the contributors, sponsors and everyone else who has helped on this project.
