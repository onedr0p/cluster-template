# Template for deploying a Kubernetes cluster backed by Flux

Welcome to my highly opinionated template for deploying a single Kubernetes ([k3s](https://k3s.io)) cluster with [Ansible](https://www.ansible.com) and managing applications with [Flux](https://toolkit.fluxcd.io/). Upon completion you will be able to expose web applications you choose to the internet with [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/).

## 👋 Introduction

The following components will be installed in your [k3s](https://k3s.io/) cluster by default. Most are only included to get a minimum viable cluster up and running.

- [flux](https://toolkit.fluxcd.io/) - GitOps operator for managing Kubernetes clusters from a Git repository
- [kube-vip](https://kube-vip.io/) - Load balancer for the Kubernetes control plane nodes
- [cert-manager](https://cert-manager.io/) - Operator to request SSL certificates and store them as Kubernetes resources
- [cilium](https://cilium.io/) - Container networking interface for inter pod and service networking
- [external-dns](https://github.com/kubernetes-sigs/external-dns) - Operator to publish DNS records to Cloudflare (and other providers) based on Kubernetes ingresses
- [k8s_gateway](https://github.com/ori-edge/k8s_gateway) - DNS resolver that provides local DNS to your Kubernetes ingresses
- [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) - Kubernetes ingress controller used for a HTTP reverse proxy of Kubernetes ingresses
- [local-path-provisioner](https://github.com/rancher/local-path-provisioner) - provision persistent local storage with Kubernetes

_Additional applications can be enabled in the [addons](./bootstrap/vars/addons.sample.yaml) configuration file_

## 📝 Pre-start checklist

Before we get started, everything below must be taken into consideration.

- [ ] Bring a **positive attitude** and be ready to learn and fail a lot. _The more you fail, the more you can learn from._
- [ ] This was designed to run in your home network on bare metal machines or VMs **NOT** in the cloud.
- [ ] You **MUST** have a domain you can manage on Cloudflare.
- [ ] Secrets will be commited to your Git repository **AND** they will be encrypted by SOPS.
- [ ] Your domain name will **NOT** be visible to the public.
- [ ] You **MUST** have a DNS server that supports split DNS (e.g. Pi-Hole) deployed somewhere outside your cluster **ON** your home network.
- [ ] You have to use nodes that have access to the internet. _This is not going to work in air-gapped environments._
- [ ] Only **amd64** and/or **arm64** nodes are supported.

With that out of the way please continue on if you are still interested...

## 💻 System Preparation

This projects supported Linux distro for running Kubernetes is Debian, Ubuntu _might_ work but it is not currently supported due to [these](https://github.com/onedr0p/flux-cluster-template/pull/830) reasons.

#### Debian for AMD64

📍 _Download the latest stable release of Debian from [here](https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/)_

There is a decent guide [here](https://www.linuxtechi.com/how-to-install-debian-12-step-by-step/) on how to get Debian installed.

1. Deviations from that guide

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
    apt install sudo
    usermod -aG sudo ${username}
    echo "${username} ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/${username}
    exit
    newgrp sudo
    sudo apt update
    ```

4. [Post install] Add SSH keys (or use `ssh-copy-id` on the client that is connecting)

    📍 _First make sure your ssh keys are up-to-date and added to your github account as [instructed](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)._

    ```sh
    mkdir -m 700 ~/.ssh
    sudo apt install curl
    curl https://github.com/${github_username}.keys > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    ```

#### Debian for RasPi4

📍 _Download the latest stable release of Debian from [here](https://raspi.debian.net/tested-images/). **Do not** use Raspbian._

If you choose to use a **RasPi4** for the cluster, it is recommended to have a 8GB model (4GB minimum). Most important is to **boot from an external SSD/NVMe**, rather than the SD card. This is supported [natively](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html), however if you have an early RasPi4, you may need to [update the bootloader](https://www.tomshardware.com/how-to/boot-raspberry-pi-4-usb).

According to the documentation [here](https://raspi.debian.net/defaults-and-settings/), after you have flashed the image onto a SSD/NVMe you must mount the drive and do the following.

1. Edit `sysconf.txt`
2. Change `root_authorized_key` to your desired public SSH key.
3. Change `root_pw` to your desired root password.
4. Change `hostname` to your desired hostname.

## 🚀 First Steps

The very first step will be to create a new **public** repository by clicking the big green **Use this template** button on this page. Next clone **your new repo** to you local workstation and `cd` into it.

📍 _**All of the below commands** are run on your **local** workstation, **not** on any of your cluster nodes._

## 🔧 Workstation Tools

📍 _Install the **most recent version** of the CLI tools below. If you are **having trouble with future steps**, it is very likely you **don't have the most recent version** of these CLI tools. The most troublesome are `ansible`, `go-task`, and `sops`._

1. Install the following CLI tools on your workstation, if you are using [Homebrew](https://brew.sh/) skip this step and move onto 2 & 3.

   - **Required**: [age](https://github.com/FiloSottile/age), [ansible](https://www.ansible.com), [flux](https://toolkit.fluxcd.io/), [cloudflared](https://github.com/cloudflare/cloudflared), [go-task](https://github.com/go-task/task), [direnv](https://github.com/direnv/direnv), [kubectl](https://kubernetes.io/docs/tasks/tools/), [python3](https://www.python.org/), [python-pip3](https://pypi.org/project/pip/), [sops](https://github.com/getsops/sops)

   - **Recommended**: [helm](https://helm.sh/), [kustomize](https://github.com/kubernetes-sigs/kustomize), [stern](https://github.com/stern/stern)

2. [Homebrew] Install [go-task](https://github.com/go-task/task)

    ```sh
    brew install go-task/tap/go-task
    ```

3. [Homebrew] Install the other workstation dependencies

    ```sh
    task brew:deps
    ```

## 🌱 Environment

Take a moment and configure [direnv](https://direnv.net/). This tool will make it so anytime you `cd` to your repo's directory it export the required environment variables (e.g. `KUBECONFIG`). To set this up make sure you [hook it into your shell](https://direnv.net/docs/hook.html) and after that is done, run `direnv allow` while in your repos directory.

## 📄 Configuration

📍 _Both `bootstrap/vars/config.yaml` and `bootstrap/vars/addons.yaml` files contain necessary information that is needed by bootstrap process._

1. Generate the `bootstrap/vars/config.yaml` and `bootstrap/vars/addons.yaml` configuration files.

    ```sh
    task init
    ```

2. Setup Age private / public key

    📍 _Using [SOPS](https://github.com/getsops/sops) with [Age](https://github.com/FiloSottile/age) allows us to encrypt secrets and use them in Ansible and Flux._

    2a. Create a Age private / public key

      ```sh
      age-keygen -o age.agekey
      ```

    2b. Create the directory for the Age key and move the Age file to it

      ```sh
      mkdir -p ~/.config/sops/age
      mv age.agekey ~/.config/sops/age/keys.txt
      ```

    2c. Fill out the appropriate vars in `bootstrap/vars/config.yaml`

3. Create Cloudflare API Token

    📍 _To use `cert-manager` with the Cloudflare DNS challenge you will need to create a API Token._

   3a. Head over to Cloudflare and create a API Token by going [here](https://dash.cloudflare.com/profile/api-tokens).

   3b. Under the `API Tokens` section click the blue `Create Token` button.

   3c. Click the blue `Use template` button for the `Edit zone DNS` template.

   3d. Name your token something like `home-kubernetes`

   3e. Under `Permissions`, click `+ Add More` and add each permission below:

    ```text
    Zone - DNS - Edit
    Account - Cloudflare Tunnel - Read
    ```

   3f. Limit the permissions to a specific account and zone resources.

   3g. Fill out the appropriate vars in `bootstrap/vars/config.yaml`

4. Create Cloudflare Tunnel

    📍 _To expose services to the internet you will need to create a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)._

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

    5a. [Optional] Update `bootstrap/vars/addons.yaml` and enable applications you would like included.

6. Once done run the following command which will verify and generate all the files needed to continue.

    ```sh
    task configure
    ```

📍 _The configure task will create a `./ansible` directory and the following directories under `./kubernetes`._

```sh
📁 kubernetes      # Kubernetes cluster defined as code
├─📁 bootstrap     # Flux installation (not tracked by Flux)
├─📁 flux          # Main Flux configuration of repository
└─📁 apps          # Apps deployed into the cluster grouped by namespace
```

## ⚡ Node Preparation

📍 _Here we will be running an Ansible playbook to prepare your nodes for running a Kubernetes cluster._

1. Ensure you are able to SSH into your nodes from your workstation using a private SSH key **without a passphrase**. For example using a SSH agent. This is how Ansible is able to connect to your remote nodes.

2. Install the Ansible deps

    ```sh
    task ansible:deps
    ```

3. Verify Ansible can view your config

    ```sh
    task ansible:list
    ```

4. Verify Ansible can ping your nodes

    ```sh
    task ansible:ping
    ```

5. Run the Ansible prepare playbook (nodes wil reboot when done)

    ```sh
    task ansible:prepare
    ```

---

## ⛵ Kubernetes Installation

📍 _Here we will be running a Ansible Playbook to install [k3s](https://k3s.io/) with [this](https://galaxy.ansible.com/xanmanning/k3s) Ansible galaxy role. If you run into problems, you can run `task ansible:nuke` to destroy the k3s cluster and start over from this point._

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

## 🔹 GitOps with Flux

📍 _Here we will be installing [flux](https://fluxcd.io/flux/) after some quick bootstrap steps._

1. Verify Flux can be installed

    ```sh
    flux check --pre
    # ► checking prerequisites
    # ✔ kubectl 1.27.3 >=1.18.0-0
    # ✔ Kubernetes 1.27.3+k3s1 >=1.16.0-0
    # ✔ prerequisites checks passed
    ```

2. Push you changes to git

   📍 **Verify** all the `*.sops.yaml` and `*.sops.yaml` files under the `./ansible`, and `./kubernetes` directories are **encrypted** with SOPS

    ```sh
    git add -A
    git commit -m "Initial commit :rocket:"
    git push
    ```

3. Install Flux and sync the cluster to the Git repository

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

## 🎤 Verification Steps

_Mic check, 1, 2_ - In a few moments applications should be lighting up like Christmas in July 🎄

1. Output all the common resources in your cluster.

    📍 _Feel free to use the provided [cluster tasks](.taskfiles/ClusterTasks.yaml) for validation of cluster resources or continue to get familiar with the `kubectl` and `flux` CLI tools._


    ```sh
    task cluster:resources
    ```

2. ⚠️ It might take `cert-manager` awhile to generate certificates, this is normal so be patient.

3. 🏆 **Congratulations** if all goes smooth you will have a Kubernetes cluster managed by Flux and your Git repository is driving the state of your cluster.

4. 🧠 Now it's time to pause and go get some motel motor oil ☕ and admire you made it this far!

## 📣 Post installation

#### 🌐 DNS

The `external-dns` application created in the `networking` namespace will handle creating public DNS records. By default, `echo-server` and the `flux-webhook` are the only public sub-domains exposed. In order to make additional applications public you must set an ingress annotation (`external-dns.alpha.kubernetes.io/target`) like done in the `HelmRelease` for `echo-server`.

For split DNS to work it is required to have `${bootstrap_cloudflare_domain}` point to the `${bootstrap_k8s_gateway_addr}` load balancer IP address on your home DNS server. This will ensure DNS requests for `${bootstrap_cloudflare_domain}` will only get routed to your `k8s_gateway` service thus providing **internal** DNS resolution to your cluster applications/ingresses from any device that uses your home DNS server.

For and example with Pi-Hole apply the following file and restart dnsmasq:

```sh
# /etc/dnsmasq.d/99-k8s-gateway-forward.conf
server=/${bootstrap_cloudflare_domain}/${bootstrap_k8s_gateway_addr}
```

Now try to resolve an internal-only domain with `dig @${pi-hole-ip} hajimari.${bootstrap_cloudflare_domain}` it should resolve to your `${bootstrap_ingress_nginx_addr}` IP.

If you're having trouble with DNS be sure to check out these two Github discussions, [Internal DNS](https://github.com/onedr0p/flux-cluster-template/discussions/719) and [Pod DNS resolution broken](https://github.com/onedr0p/flux-cluster-template/discussions/635).

Nothing working? That is expected, this is DNS after all!

#### 📜 Certificates

By default this template will deploy a wildcard certificate with the Let's Encrypt staging servers. This is to prevent you from getting rate-limited on configuration that might not be valid on bootstrap using the production server. If you had `bootstrap_acme_production_enabled` set to `false` in your `bootstrap/vars/config.yaml`, make sure to switch to the Let's Encrypt production servers as outlined in that file. Do not enable the production certificate until you are sure you will keep the cluster up for more than a few hours.

#### 🤖 Renovatebot

[Renovatebot](https://www.mend.io/free-developer-tools/renovate/) will scan your repository and offer PRs when it finds dependencies out of date. Common dependencies it will discover and update are Flux, Ansible Galaxy Roles, Terraform Providers, Kubernetes Helm Charts, Kubernetes Container Images, and more!

The base Renovate configuration provided in your repository can be view at [.github/renovate.json5](https://github.com/onedr0p/flux-cluster-template/blob/main/.github/renovate.json5). If you notice this only runs on weekends and you can [change the schedule to anything you want](https://docs.renovatebot.com/presets-schedule/) or simply remove it.

To enable Renovate on your repository, click the 'Configure' button over at their [Github app page](https://github.com/apps/renovate) and choose your repository. Over time Renovate will create PRs for out-of-date dependencies it finds. Any merged PRs that are in the kubernetes directory Flux will deploy.

#### 🪝 Github Webhook

Flux is pull-based by design meaning it will periodically check your git repository for changes, using a webhook you can enable Flux to update your cluster on `git push`. In order to configure Github to send `push` events from your repository you must find your hook id that is already generated.

1. Obtain the hook id and path

    ```sh
    kubectl -n flux-system get receiver github-receiver -o jsonpath='{.status.webhookPath}'
    /hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

2. Piece your full URL with the hook path appended

    ```text
    https://flux-webhook.${bootstrap_cloudflare_domain}/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

3. Navigate to the settings of your repository on Github, under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook url and your `bootstrap_flux_github_webhook_token` secret.

#### 🔏 Authenticate Flux over SSH

Authenticating Flux to your git repository has a couple benefits like using a private git repository and/or using the Flux [Image Automation Controllers](https://fluxcd.io/docs/components/image/).

By default this template only works on a public GitHub repository, it is advised to keep your repository public.

The benefits of a public repository include:

- Debugging or asking for help, you can provide a link to a resource you are having issues with.
- Adding a topic to your repository of `k8s-at-home` to be included in the [k8s-at-home-search](https://nanne.dev/k8s-at-home-search/). This search helps people discover different configurations of Helm charts across others Flux based repositories.

<details>
  <summary>Expand to read guide on adding Flux SSH authentication</summary>

1. Generate new SSH key:

    ```sh
    ssh-keygen -t ecdsa -b 521 -C "github-deploy-key" -f ./kubernetes/bootstrap/github-deploy.key -q -P ""
    ```

2. Paste public key in the deploy keys section of your repository settings
3. Create sops secret in `./kubernetes/bootstrap/github-deploy-key.sops.yaml` with the contents of:

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: github-deploy-key
     namespace: flux-system
   stringData:
     # 3a. Contents of github-deploy-key
     identity: |
       -----BEGIN OPENSSH PRIVATE KEY-----
           ...
       -----END OPENSSH PRIVATE KEY-----
     # 3b. Output of curl --silent https://api.github.com/meta | jq --raw-output '"github.com "+.ssh_keys[]'
     known_hosts: |
       github.com ssh-ed25519 ...
       github.com ecdsa-sha2-nistp256 ...
       github.com ssh-rsa ...
   ```

4. Encrypt secret:

    ```sh
    sops --encrypt --in-place ./kubernetes/bootstrap/github-deploy-key.sops.yaml
    ```

5. Apply secret to cluster:

    ```sh
    sops --decrypt ./kubernetes/bootstrap/github-deploy-key.sops.yaml | kubectl apply -f -
    ```

6. Update `./kubernetes/flux/config/cluster.yaml`:

    ```yaml
    apiVersion: source.toolkit.fluxcd.io/v1beta2
    kind: GitRepository
    metadata:
      name: home-kubernetes
      namespace: flux-system
    spec:
      interval: 10m
      # 6a: Change this to your user and repo names
      url: ssh://git@github.com/$user/$repo
      ref:
        branch: main
      secretRef:
        name: github-deploy-key
    ```

7. Commit and push changes
8. Force flux to reconcile your changes

    ```sh
    flux reconcile -n flux-system kustomization cluster --with-source
    ```

9. Verify git repository is now using SSH:

    ```sh
    flux get sources git -A
    ```

10. Optionally set your repository to Private in your repository settings.

</details>

#### 💾 Storage

Rancher's `local-path-provisioner` is a great start for storage but soon you might find you need more features like replicated block storage, or to connect to a NFS/SMB/iSCSI server. Check out the projects below to read up more on some storage solutions that might work for you.

- [rook-ceph](https://github.com/rook/rook)
- [longhorn](https://github.com/longhorn/longhorn)
- [openebs](https://github.com/openebs/openebs)
- [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)
- [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)
- [synology-csi](https://github.com/SynologyOpenSource/synology-csi)

## 🐛 Debugging

Below is a general guide on trying to debug an issue with an resource or application. For example, if a workload/resource is not showing up or a pod has started but in a `CrashLoopBackOff` or `Pending` state.

1. Start by checking all Flux Kustomizations & Git Repository & OCI Repository and verify they are healthy.

    ```sh
    flux get sources oci -A
    flux get sources git -A
    flux get ks -A
    ```

2. Then check all the Flux Helm Releases and verify they are healthy.

    ```sh
    flux get hr -A
    ```

3. Then check the if the pod is present.

    ```sh
    kubectl -n <namespace> get pods -o wide
    ```

4. Then check the logs of the pod if its there.

    ```sh
    kubectl -n <namespace> logs <pod-name> -f
    # or
    stern -n <namespace> <fuzzy-name>
    ```

5. If a resource exists try to describe it to see what problems it might have.

    ```sh
    kubectl -n <namespace> describe <resource> <name>
    ```

6. Check the namespace events

    ```sh
    kubectl get events -n <namespace> --sort-by='.metadata.creationTimestamp'
    ```

Resolving problems that you have could take some tweaking of your YAML manifests in order to get things working, other times it could be a external factor like permissions on NFS. If you are unable to figure out your problem see the help section below.

## 👉 Help

- Make a post in this repository's GitHub [Discussions](https://github.com/onedr0p/flux-cluster-template/discussions).
- Start a thread in the `support` or `flux-cluster-template` channel in the [k8s@home](https://discord.gg/k8s-at-home) Discord server.

## ❔ What's next

The world is your cluster, have at it!

## 🤝 Thanks

Big shout out to all the authors and contributors to the projects that we are using in this repository.

[@whazor](https://github.com/whazor) created [this website](https://nanne.dev/k8s-at-home-search/) as a creative way to search Helm Releases across GitHub. You may use it as a means to get ideas on how to configure an applications' Helm values.
