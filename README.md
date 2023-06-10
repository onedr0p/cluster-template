# 89t k8s cluster

This cluster is built from this great repo: <https://github.com/onedr0p/flux-cluster-template>.

The hardware is a mix of baremetal ARM (arm64 or aarch64) and x86 (arm64) nodes. Originally I had intended to go purely ARM, but a sudden increase in affordability of x86 embedded hardware, and, the fact that many operators (including the postgres operator installed), fail to deploy on ARM.

I was surprised to find out that running a mixed architecture cluster is easier than single architecture when you are primarily trying to orchestrate a bunch of cloud native software.

There are a couple additional kubernetes apps installed:

- rook-ceph
  - encryption turned on
  - OSDs are on nvme drives, and configured per device
  - provides default backing for the following persistent volumes classes:
    - block
    - filesystem
    - object
- postgres-operator
  - relies on rook-ceph for persistent storage
  - node affinity to ensure it runs on x86 nodes

If you are here because you want a cluster that has something this cluster has, and the one above isn't quite scratching the itch, please do us both a favor and read my notes, then go through everything at the above repo, then come back here.

- Baremetal: if you are not on baremetal, you are in the wrong place. [kube-vip](https://kube-vip.io/docs/installation/static/#arp), [MetalLB](https://metallb.universe.tf/concepts/) and to a large extent, [cloudflared](https://github.com/cloudflare/cloudflared) are of no value within a cloud or virtual environment, there are much better solutions.

- Networking: Think about what your networking looks like. I'd suggest setting up your subnet to work with the defaults rather than try and change the network to match your subnet. I have a "real" interface coming off a switch, which takes the IP 10.10.1.1/24 and serves DHCP. Each mac address which gets a reservation has its first IP permanently reserved (so it acts like a static IP). I plug directly into that switch to operate on the cluster, but I also have a jump box set up, and allow ingress from the management LAN of my home network.

- Drives: You might be excited to run a cluster from a bunch of dev boards; which is how this started out. Most of these dev boards only have 1 nvme slot. 2 of my control nodes boots from an A2 TF card, one of the workers boots from a usb-c. The one of the A2 boot is an arm64 which uses XFS (nearly 50% faster than its ext4 counterpart on big writes). The usb-c is using btrfs. 2 of the three worker nodes are booting from nvme and use it for the whoel filesystem. I did not do any actual benchmarking, but I built many clusters with just the TF card as boot devices, and I was surprised at how little difference ext4 nvme vs A2 tf cards for root filesystems would be. Throughput for container syncing was much faster on the nvmes, but they had no problem keeping up with operations.
  a. Eventually I'd like to have the ETCD cluster be backed by ceph data, but until then I will leave the 2 NVME masters.
  b. for worker nodes, dedicating 4GB and an m.2 slot to ceph cluster probably makes sense for dev boards, but for your control nodes, its a bit tougher.

## Additions

### Rook (Ceph)

Ceph has traditionally been run in its own cluster, and Rook allows us to orchestrate a Ceph cluster within our Kubernetes cluster. The most important thing to look at when configuring ceph is the device configuration. The easiest way by far is to just plug in brand new disks and set `useAllNodes` to true; and the cluster will happily slurp everything right up.

However, be warned, a default configuration of an OSD (the daemon which manages the disk) with all the monitoring/alerting etc is 4GB in memory requests. By default there will be a single OSD per configured device; this cluster has a variety; a low memory worker with a 2tb nvme has only a single OSD; while a high memory worker with 2x2tb nvme has 8 OSDs between them.

If like me, it takes you about 100 iterations before the cluster comes up the way you like; there are many types of fingerprints that can be left behind which will have ceph refuse to provision the disks. The most common are latent partitions, but with encryption enabled; there are other block-device-level artifacts that remain, after you thought you were starting fresh.

As such, there are a couple additional ansible scripts; the primary one I would recommend using is `task ansible:rancher-nuke`; as it will delete the /var/lib/rancher directory which the parent repo of this one chooses not to. Without removing this directory, many container artifacts stick around between installs, which operators tend to not like.

If you are using encryption (which this repo is), you will also need to clean the ceph level artifacts off the block devices, which you can do with `task ansible:ceph-nuke` if you have non-nvme drives that need to be cleaned, this script may not work without manually unmounting them, but look into `sgdisk` to see more about what is going on there.

### Configuration

`task ansible:configure` has been disabled; it is very useful to significaly shorten the iteration loop when getting started, so I do not suggest that you also disable it before you've begun; however, I have slighly cusotmized the ansible yaml in a way that would be overwritten by re-running that configuration generation script, and those changes are not going upstream into the configurator. If you want to follow along with this repository, I suggest starting from the one [I started from](https://github.com/onedr0p/flux-cluster-template), and then once the config is generated, just edit the ansible yaml directly as necessary.

### OLM - Operator Lifecycle Manager

OLM has gone out of their way to not provide a helm chart for installation, insisting that their installation be T[he One Exception](https://github.com/operator-framework/operator-lifecycle-manager/issues/829) declarative config. We ~~are~~ were following an external chart which tracks the OLM chart repository and installs the OLM operator. OLM is archaic at this point and antithetical to the design principles of kubernetes. It is a shame that it is the only way to install some operators, but it is what it is. (this paragraph almost entirely created by github copilot).

I have removed OLM and suggest that you do not bother with it if you are on baremetal and are not interested in a layer of virtualization on top. If you are on a cloud provider, you may want to look into it, but I have not found it to be useful.

## 📂 Repository structure

The Git repository contains the following directories under `kubernetes` and are ordered below by how Flux will apply them.

```sh
📁 kubernetes      # Kubernetes cluster defined as code
├─📁 bootstrap     # Flux installation
├─📁 flux          # Main Flux configuration of repository
└─📁 apps          # Apps deployed into the cluster grouped by namespace
```

### Requirements

📍 Install the **most recent version** of the CLI tools below. If you are **having trouble with future steps**, it is very likely you don't have the most recent version of these CLI tools, **!especially sops AND yq!**.

1. Install the following CLI tools on your workstation, if you are **NOT** using [Homebrew](https://brew.sh/) on MacOS or Linux **ignore** steps 4 and 5.

   - Required: [age](https://github.com/FiloSottile/age), [ansible](https://www.ansible.com), [flux](https://toolkit.fluxcd.io/), [weave-gitops](https://docs.gitops.weave.works/docs/installation/weave-gitops/), [cloudflared](https://github.com/cloudflare/cloudflared), [cilium-cli](https://github.com/cilium/cilium-cli), [go-task](https://github.com/go-task/task), [direnv](https://github.com/direnv/direnv), [ipcalc](http://jodies.de/ipcalc), [jq](https://stedolan.github.io/jq/), [kubectl](https://kubernetes.io/docs/tasks/tools/), [python-pip3](https://pypi.org/project/pip/), [pre-commit](https://github.com/pre-commit/pre-commit), [sops v3](https://github.com/mozilla/sops), [yq v4](https://github.com/mikefarah/yq)

   - Recommended: [helm](https://helm.sh/), [kustomize](https://github.com/kubernetes-sigs/kustomize), [stern](https://github.com/stern/stern), [yamllint](https://github.com/adrienverge/yamllint)

2. This guide heavily relies on [go-task](https://github.com/go-task/task) as a framework for setting things up. It is advised to learn and understand the commands it is running under the hood.

3. Install Python 3 and pip3 using your Linux OS package manager, or Homebrew if using MacOS.

   - Ensure `pip3` is working on your command line by running `pip3 --version`

4. [Homebrew] Install [go-task](https://github.com/go-task/task)

   ```sh
   brew install go-task/tap/go-task
   ```

5. [Homebrew] Install workstation dependencies

   ```sh
   task init
   ```

### ⚠️ pre-commit

It is advisable to install [pre-commit](https://pre-commit.com/) and the pre-commit hooks that come with this repository.

1. Enable Pre-Commit

   ```sh
   task precommit:init
   ```

2. Update Pre-Commit, though it will occasionally make mistakes, so verify its results.

   ```sh
   task precommit:update
   ```

### 🔐 Setting up Age

📍 Here we will create a Age Private and Public key. Using [SOPS](https://github.com/mozilla/sops) with [Age](https://github.com/FiloSottile/age) allows us to encrypt secrets and use them in Ansible and Flux.

1. Create a Age Private / Public Key

   ```sh
   age-keygen -o age.agekey
   ```

2. Set up the directory for the Age key and move the Age file to it

   ```sh
   mkdir -p ~/.config/sops/age
   mv age.agekey ~/.config/sops/age/keys.txt
   ```

3. Export the `SOPS_AGE_KEY_FILE` variable in your `bashrc`, `zshrc` or `config.fish` and source it, e.g.

   ```sh
   export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
   source ~/.bashrc
   ```

4. Fill out the Age public key in the appropriate variable in configuration section below, **note** the public key should start with `age`...

### ☁️ Cloudflare API Key

In order to use `cert-manager` with the Cloudflare DNS challenge you will need to create a API key.

1. Head over to Cloudflare and create a API key by going [here](https://dash.cloudflare.com/profile/api-tokens).

2. Under the `API Keys` section, create a global API Key.

3. Use the API Key in the appropriate variable in configuration section below.

📍 You may wish to update this later on to a Cloudflare **API Token** which can be scoped to certain resources. I do not recommend using a Cloudflare **API Key**, however for the purposes of this template it is easier getting started without having to define which scopes and resources are needed. For more information see the [Cloudflare docs on API Keys and Tokens](https://developers.cloudflare.com/api/).

### ☁️ Cloudflare Tunnel

In order to expose services to the internet you will need to create a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/).

1. Authenticate cloudflared to your domain

   ```sh
   cloudflared tunnel login
   ```

2. Create the tunnel

   ```sh
   cloudflared tunnel create k8s
   ```

3. In the `~/.cloudflared` directory there will be a json file with details you need to populate in configuration section below. You can ignore the `cert.pem` file.

### 📄 Configuration

📍 The `.config.env` file contains necessary configuration that is needed by Ansible and Flux.

1. Copy the `.config.sample.env` to `.config.env` and start filling out all the environment variables.

   **All are required** unless otherwise noted in the comments.

   ```sh
   cp .config.sample.env .config.env
   ```

2. Once that is done, verify the configuration is correct by running:

   ```sh
   task verify
   ```

3. If you do not encounter any errors run start having the script wire up the templated files and place them where they need to be.

   ```sh
   task configure
   ```

⚠️ This will print out the clear-text passwords for Grafana and Weave Gitops if you had them set to `generated` in your `.config.env`. Take note of these, you'll need them to log into the applications.

### ⚡ Preparing Ubuntu Server with Ansible

1. Ensure you are able to SSH into your nodes from your workstation using a private SSH key **without a passphrase**. This is how Ansible is able to connect to your remote nodes.

   [How to configure SSH key-based authentication](https://www.digitalocean.com/community/tutorials/how-to-configure-ssh-key-based-authentication-on-a-linux-server)

2. Install the Ansible deps

   ```sh
   task ansible:init
   ```

3. Verify Ansible can view your config

   ```sh
   task ansible:list
   ```

4. Verify Ansible can ping your nodes

   ```sh
   task ansible:ping
   ```

5. Run the Ansible prepare playbook

   ```sh
   task ansible:prepare
   ```

6. Reboot the nodes (if not done in step 5)

   ```sh
   task ansible:force-reboot
   ```

### ⛵ Installing k3s with Ansible

📍 Here we will be running a Ansible Playbook to install [k3s](https://k3s.io/) with [this](https://galaxy.ansible.com/xanmanning/k3s) wonderful k3s Ansible galaxy role. After completion, Ansible will drop a `kubeconfig` in `./kubeconfig` for use with interacting with your cluster with `kubectl`.

☢️ If you run into problems, you can run `task ansible:nuke` to destroy the k3s cluster and start over.

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

   ```sh
   task cluster:nodes
   # NAME           STATUS   ROLES                       AGE     VERSION
   # k8s-0          Ready    control-plane,master      4d20h   v1.21.5+k3s1
   # k8s-1          Ready    worker                    4d20h   v1.21.5+k3s1
   ```

### 🔹 GitOps with Flux

📍 Here we will be installing [flux](https://toolkit.fluxcd.io/) after some quick bootstrap steps.

1. Verify Flux can be installed

   ```sh
   task cluster:verify
   # ► checking prerequisites
   # ✔ kubectl 1.21.5 >=1.18.0-0
   # ✔ Kubernetes 1.21.5+k3s1 >=1.16.0-0
   # ✔ prerequisites checks passed
   ```

2. Push you changes to git

   📍 **Verify** all the `*.sops.yaml` and `*.sops.yml` files under the `./ansible`, and `./kubernetes` directories are **encrypted** with SOPS

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
   ```

4. Verify Flux components are running in the cluster

   ```sh
   task cluster:pods -- -n flux-system
   # NAME                                       READY   STATUS    RESTARTS   AGE
   # helm-controller-5bbd94c75-89sb4            1/1     Running   0          1h
   # kustomize-controller-7b67b6b77d-nqc67      1/1     Running   0          1h
   # notification-controller-7c46575844-k4bvr   1/1     Running   0          1h
   # source-controller-7d6875bcb4-zqw9f         1/1     Running   0          1h
   ```

### 🎤 Verification Steps

_Mic check, 1, 2_ - In a few moments applications should be lighting up like a Christmas tree 🎄

You are able to run all the commands below with one task

```sh
task cluster:resources
```

1. View the Flux Git Repositories

   ```sh
   task cluster:gitrepositories
   ```

2. View the Flux kustomizations

   ```sh
   task cluster:kustomizations
   ```

3. View all the Flux Helm Releases

   ```sh
   task cluster:helmreleases
   ```

4. View all the Flux Helm Repositories

   ```sh
   task cluster:helmrepositories
   ```

5. View all the Pods

   ```sh
   task cluster:pods
   ```

6. View all the certificates and certificate requests

   ```sh
   task cluster:certificates
   ```

7. View all the ingresses

   ```sh
   task cluster:ingresses
   ```

☢️ If you run into problems, you can run `task ansible:nuke` to destroy the k3s cluster and start over.

## 📣 Post installation

### 🌱 Environment

[direnv](https://direnv.net/) will make it so anytime you `cd` to your repo's directory it export the required environment variables (e.g. `KUBECONFIG`). To set this up make sure you [hook it into your shell](https://direnv.net/docs/hook.html) and after that is done, run `direnv allow` while in your repos directory.

### 🌐 DNS

📍 The `external-dns` application created in the `networking` namespace will handle creating public DNS records. By default, `echo-server` and the `flux-webhook` are the only public sub-domains exposed. In order to make additional applications public you must set an ingress annotation (`external-dns.alpha.kubernetes.io/target`) like done in the `HelmRelease` for `echo-server`.

For split DNS to work it is required to have `${SECRET_DOMAIN}` point to the `${METALLB_K8S_GATEWAY_ADDR}` load balancer IP address on your home DNS server. This will ensure DNS requests for `${SECRET_DOMAIN}` will only get routed to your `k8s_gateway` service thus providing **internal** DNS resolution to your cluster applications/ingresses from any device that uses your home DNS server.

For and example with Pi-Hole apply the following file and restart dnsmasq:

```sh
# /etc/dnsmasq.d/99-k8s-gateway-forward.conf
server=/${SECRET_DOMAIN}/${METALLB_K8S_GATEWAY_ADDR}
```

Now try to resolve an internal-only domain with `dig @${pi-hole-ip} hajimari.${SECRET_DOMAIN}` it should resolve to your `${METALLB_INGRESS_ADDR}` IP.

If having trouble you can ask for help in [this](https://github.com/onedr0p/flux-cluster-template/discussions/719) Github discussion.

If nothing is working, that is expected. This is DNS after all!

### 🤖 Renovatebot

[Renovatebot](https://www.mend.io/free-developer-tools/renovate/) will scan your repository and offer PRs when it finds dependencies out of date. Common dependencies it will discover and update are Flux, Ansible Galaxy Roles, Terraform Providers, Kubernetes Helm Charts, Kubernetes Container Images, Pre-commit hooks updates, and more!

The base Renovate configuration provided in your repository can be view at [.github/renovate.json5](https://github.com/onedr0p/flux-cluster-template/blob/main/.github/renovate.json5). If you notice this only runs on weekends and you can [change the schedule to anything you want](https://docs.renovatebot.com/presets-schedule/) or simply remove it.

To enable Renovate on your repository, click the 'Configure' button over at their [Github app page](https://github.com/apps/renovate) and choose your repository. Over time Renovate will create PRs for out-of-date dependencies it finds. Any merged PRs that are in the kubernetes directory Flux will deploy.

### 🪝 Github Webhook

Flux is pull-based by design meaning it will periodically check your git repository for changes, using a webhook you can enable Flux to update your cluster on `git push`. In order to configure Github to send `push` events from your repository to the Flux webhook receiver you will need two things:

1. Webhook URL - Your webhook receiver will be deployed on `https://flux-webhook.${BOOTSTRAP_CLOUDFLARE_DOMAIN}/hook/:hookId`. In order to find out your hook id you can run the following command:

   ```sh
   kubectl -n flux-system get receiver/github-receiver
   # NAME              AGE    READY   STATUS
   # github-receiver   6h8m   True    Receiver initialized with URL: /hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
   ```

   So if my domain was `onedr0p.com` the full url would look like this:

   ```text
   https://flux-webhook.onedr0p.com/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
   ```

2. Webhook secret - Your webhook secret can be found by decrypting the `secret.sops.yaml` using the following command:

   ```sh
   sops -d ./kubernetes/apps/flux-system/addons/webhooks/github/secret.sops.yaml | yq .stringData.token
   ```

   **Note:** Don't forget to update the `BOOTSTRAP_FLUX_GITHUB_WEBHOOK_SECRET` variable in your `.config.env` file so it matches the generated secret if applicable

Now that you have the webhook url and secret, it's time to set everything up on the Github repository side. Navigate to the settings of your repository on Github, under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook url and your secret.

### 💾 Storage

Rancher's `local-path-provisioner` is a great start for storage but soon you might find you need more features like replicated block storage, or to connect to a NFS/SMB/iSCSI server. Check out the projects below to read up more on some storage solutions that might work for you.

- [rook-ceph](https://github.com/rook/rook)
- [longhorn](https://github.com/longhorn/longhorn)
- [openebs](https://github.com/openebs/openebs)
- [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)
- [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)
- [synology-csi](https://github.com/SynologyOpenSource/synology-csi)

### 🔏 Authenticate Flux over SSH

Authenticating Flux to your git repository has a couple benefits like using a private git repository and/or using the Flux [Image Automation Controllers](https://fluxcd.io/docs/components/image/).

By default this template only works on a public GitHub repository, it is advised to keep your repository public.

The benefits of a public repository include:

- Debugging or asking for help, you can provide a link to a resource you are having issues with.
- Adding a topic to your repository of `k8s-at-home` to be included in the [k8s-at-home-search](https://whazor.github.io/k8s-at-home-search/). This search helps people discover different configurations of Helm charts across others Flux based repositories.

Adding Flux SSH authentication

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
   task cluster:reconcile
   ```

9. Verify git repository is now using SSH:

   ```sh
   task cluster:gitrepositories
   ```

10. Optionally set your repository to Private in your repository settings.

### 💨 Kubernetes Dashboard

Included in your cluster is the [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/). Inorder to log into this you will have to get the secret token from the cluster using the command below.

```sh
kubectl -n monitoring get secret kubernetes-dashboard -o jsonpath='{.data.token}' | base64 -d
```

You should be able to access the dashboard at `https://kubernetes.${SECRET_DOMAIN}`

## 🐛 Debugging

Below is a general guide on trying to debug an issue with an resource or application. For example, if a workload/resource is not showing up or a pod has started but in a `CrashLoopBackOff` or `Pending` state.

1. Start by checking all Flux Kustomizations & Git Repository & OCI Repository and verify they are healthy.

   - `flux get sources oci -A`
   - `flux get sources git -A`
   - `flux get ks -A`

2. Then check all the Flux Helm Releases and verify they are healthy.

   - `flux get hr -A`

3. Then check the if the pod is present.

   - `kubectl -n <namespace> get pods`

4. Then check the logs of the pod if its there.

   - `kubectl -n <namespace> logs <pod-name> -f`

Note: If a resource exists, running `kubectl -n <namespace> describe <resource> <name>` might give you insight into what the problem(s) could be.

Resolving problems that you have could take some tweaking of your YAML manifests in order to get things working, other times it could be a external factor like permissions on NFS. If you are unable to figure out your problem see the help section below.

## 👉 Help

- Make a post in this repository's GitHub [Discussions](https://github.com/onedr0p/flux-cluster-template/discussions).
- Start a thread in the `support` or `flux-cluster-template` channel in the [k8s@home](https://discord.gg/k8s-at-home) Discord server.

## ❔ What's next

The world is your cluster, have at it!

## 🤝 Thanks

Big shout out to all the authors and contributors to the projects that we are using in this repository.

[@whazor](https://github.com/whazor) created [this website](https://nanne.dev/k8s-at-home-search/) as a creative way to search Helm Releases across GitHub. You may use it as a means to get ideas on how to configure an applications' Helm values.
