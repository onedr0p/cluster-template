# ⛵ Cluster Template

Welcome to my template designed for deploying a single Kubernetes cluster. Whether you're setting up a cluster at home on bare-metal or virtual machines (VMs), this project aims to simplify the process and make Kubernetes more accessible. This template is inspired by my personal [home-ops](https://github.com/onedr0p/home-ops) repository, providing a practical starting point for anyone interested in managing their own Kubernetes environment.

At its core, this project uses [makejinja](https://github.com/mirkolenz/makejinja) to render the Talos, Kubernetes and Flux configuration for your cluster from a single [cluster.toml](./cluster.sample.toml) file, validated and defaulted by [pydantic](https://docs.pydantic.dev/).

## ✨ Features

A Kubernetes cluster deployed with [Talos Linux](https://github.com/siderolabs/talos) and an opinionated implementation of [Flux](https://github.com/fluxcd/flux2) syncing from the Git provider of your choice (GitHub, GitLab, Gitea, Forgejo, Codeberg or self-hosted), [sops](https://github.com/getsops/sops) to manage secrets and [cloudflared](https://github.com/cloudflare/cloudflared) to access applications external to your local network.

- **Required:** Some knowledge of [Containers](https://opencontainers.org/), [YAML](https://noyaml.com/), [Git](https://git-scm.com/), and a **domain**. Exposing apps to the public internet requires a **Cloudflare account**; internal-only clusters don't.
- **Included components:** [flux](https://github.com/fluxcd/flux2), [cilium](https://github.com/cilium/cilium), [cert-manager](https://github.com/cert-manager/cert-manager), [spegel](https://github.com/spegel-org/spegel), [reloader](https://github.com/stakater/Reloader), [coredns](https://github.com/coredns/coredns), [metrics-server](https://github.com/kubernetes-sigs/metrics-server) and [prometheus-operator-crds](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds). The template also includes [k8s_gateway](https://github.com/k8s-gateway/k8s_gateway), [envoy-gateway](https://github.com/envoyproxy/gateway), [external-dns](https://github.com/kubernetes-sigs/external-dns) and [cloudflared](https://github.com/cloudflare/cloudflared) for DNS and ingress.

**Other features include:**

- Dev env and tasks managed w/ [mise](https://mise.jdx.dev/)
- Workflow automation w/ [GitHub Actions](https://github.com/features/actions)
- Dependency automation w/ [Renovate](https://www.mend.io/renovate)
- Flux `HelmRelease` and `Kustomization` diffs w/ [flate](https://github.com/home-operations/flate)

Does this sound cool to you? If so, continue to read on! 👇

## 🚀 Let's Go!

There are **6 stages** outlined below for completing this project, make sure you follow the stages in order.

### Stage 1: Hardware Configuration

For a **stable** and **high-availability** Kubernetes cluster, hardware selection is critical:

- **Bare Metal is strongly recommended** over virtualized platforms like Proxmox. Proxmox with enterprise drives can work for testing or carefully tuned clusters, but adds layers of potential I/O contention, especially with consumer drives.
- **Enterprise NVMe or SATA SSDs** (even used drives) are the most reliable. Consumer SSDs carry risks such as latency spikes, corruption and fsync delays, particularly in multi-node setups. Avoid HDDs.
- **Replicated storage** (e.g., Rook-Ceph, Longhorn) should always use **dedicated disks separate from control plane and etcd nodes**. Worker nodes are more flexible, but avoid risky configurations for stateful workloads.

These guidelines are a baseline, not a guarantee: **test and benchmark** your hardware under realistic workloads.

> [!IMPORTANT]
> If you have **3 or more nodes** it is recommended to make 3 of them controller nodes for a highly available control plane. This project configures **all nodes** to be able to run workloads. **Worker nodes** are therefore **optional**.
>
> **Minimum system requirements**
>
> | Role           | Cores | Memory | System Disk    |
> | -------------- | ----- | ------ | -------------- |
> | Control/Worker | 4     | 16GB   | 256GB SSD/NVMe |

### Stage 2: Machine Preparation

1. Head over to the [Talos Linux Image Factory](https://factory.talos.dev) and follow the instructions. Be sure to only choose the **bare-minimum system extensions** as some might require additional configuration and prevent Talos from booting without it. Depending on your CPU start with the Intel/AMD system extensions (`i915`, `intel-ucode` & `mei` **or** `amdgpu` & `amd-ucode`), you can always add system extensions after Talos is installed and working.

2. This will eventually lead you to download a Talos Linux ISO (or for SBCs a RAW) image. Make sure to note the **schematic ID** you will need this later on.

3. Flash the Talos ISO or RAW image to a USB drive and boot from it on your nodes.

4. Verify with `nmap` that your nodes are available on the network. (Replace `192.168.1.0/24` with the network your nodes are on.)

    ```sh
    nmap -Pn -n -p 50000 192.168.1.0/24 -vv | grep 'Discovered'
    ```

### Stage 3: Local Workstation

> [!TIP]
> It is recommended to set the visibility of your repository to `Public` so you can easily request help if you get stuck.

1. Create a new repository by clicking the green `Use this template` button at the top of this page, then clone the new repo you just created and `cd` into it. Alternatively you can use the [GitHub CLI](https://cli.github.com/) ...

    ```sh
    export REPONAME="home-ops"
    gh repo create $REPONAME --template onedr0p/cluster-template --public --clone
    cd $REPONAME
    ```

    📍 _**Not using GitHub?** Any Git provider works (GitLab, Gitea, Forgejo, Codeberg or self-hosted). Create an empty repository on your provider, download this template with `git clone --depth 1 https://github.com/onedr0p/cluster-template`, re-initialize it with `git init` and push it to your repository._

2. **Install** the [Mise CLI](https://mise.jdx.dev/getting-started.html#installing-mise-cli) on your local workstation.

3. **Activate** Mise in your shell by following the [activation guide](https://mise.jdx.dev/getting-started.html#activate-mise).

4. Use `mise` to install the **required** CLI tools:

    ```sh
    mise trust
    mise install
    ```

    📍 _**Having trouble installing the tools?** Try unsetting the `GITHUB_TOKEN` env var and then run these commands again_

    📍 _**Commands later fail with `command not found` or `unknown command`?** `mise` is either not installed, not activated in your shell, or configured incorrectly._

    📍 _**Platforms:** `.mise/mise.lock` locks tool downloads for Linux and macOS on amd64 and arm64, and always for your own platform even when it is not one of these. If you also need musl (e.g. Alpine) or Windows, add `linux-x64-musl`, `linux-arm64-musl` or `windows-x64` to `lockfile_platforms` in `.mise/config.toml`, run `mise lock`, and commit both files._

5. Logout of the GitHub Container Registry as this may cause authorization problems in future steps when using the public registry:

    ```sh
    docker logout ghcr.io
    helm registry logout ghcr.io
    ```

### Stage 4: Cloudflare configuration

> [!TIP]
> **Internal-only cluster?** Set `provider = "none"` under `[dns]` in `cluster.toml` and skip this stage entirely: no Cloudflare account, API token, or `cloudflare-tunnel.json` is needed. Nothing is exposed to the internet, apps are reachable on your LAN via the internal gateway, and the wildcard certificate is issued by an in-cluster self-signed CA instead of Let's Encrypt.

> [!TIP]
> **Public cluster on another DNS host?** Set `provider = "none"` under `[dns]` and `mode = "direct"` under `[ingress]`, and skip this stage. Instead, forward TCP 443 (and optionally 80) on your router to the `gateways.external` IP, point `external.<domain>` at your WAN address and create the per-app records yourself (e.g. a `*.<domain>` CNAME to `external.<domain>`). The wildcard certificate then comes from the in-cluster CA, which public clients and Git webhooks do not trust (so `webhook_provider` defaults to `"none"`); for a trusted one, bring your own ClusterIssuer and set `cluster_issuer` under `[certs]` as described in `cluster.sample.toml`.

1. Create a Cloudflare API token for use with cloudflared and external-dns by reviewing the official [documentation](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/) and following the instructions below.

    - Click the blue `Use template` button for the `Edit zone DNS` template.
    - Name your token `kubernetes`
    - Under `Permissions`, click `+ Add More` and add permissions `Zone - DNS - Edit` and `Account - Cloudflare Tunnel - Read`
    - Limit the permissions to a specific account and/or zone resources and then click `Continue to Summary` and then `Create Token`.
    - **Save this token somewhere safe**, you will need it later on.

2. Create the Cloudflare Tunnel:

    ```sh
    cloudflared tunnel login
    cloudflared tunnel create --credentials-file cloudflare-tunnel.json kubernetes
    ```

    📍 _**Prefer port-forwarding over a tunnel?** Set `mode = "direct"` under `[ingress]` in `cluster.toml` and skip this step: no `cloudflare-tunnel.json` is needed. Instead, forward TCP 443 (and optionally 80) on your router to the external gateway's address (the `gateways.external` IP, or a node IP when it uses `load_balancer_class = "io.cilium/node"`; with `cilium.announce` set to `"bgp"` or `"none"` your router must route that address to the nodes), and create an `external.<domain>` DNS record yourself pointing at your WAN address (an A record, or a CNAME to a DDNS hostname). Per-app records are still published automatically._

### Stage 5: Cluster configuration

1. Generate the config files from the sample files:

    ```sh
    mise run init
    ```

2. Fill out the `cluster.toml` configuration file using the comments in it as a guide. Editors with TOML schema support (VS Code's Even Better TOML, taplo in Neovim) pick up the `#:schema` directive at the top of the file and provide completion and inline validation.

3. Template out the kubernetes and talos configuration files, if any issues come up be sure to read the error and adjust your config files accordingly.

    📍 _Run `mise doctor project` to check that every file the template needs is in place._

    ```sh
    mise run configure
    ```

4. Push your changes to git:

    📍 _**Verify** all the `./bootstrap/**/*.sops.*`, `./kubernetes/**/*.sops.*` and `./talos/secrets.sops.yaml` files are **encrypted** with SOPS_

    ```sh
    git add -A
    git commit -m "chore: initial commit :rocket:"
    git push
    ```

> [!TIP]
> Using a **private repository** (an `ssh://` URL in `cluster.toml`)? Make sure to paste the public key from `deploy.key.pub` into the deploy keys section of your repository settings (GitHub: `Settings/Deploy keys`, GitLab: `Settings/Repository/Deploy keys`, Gitea/Forgejo: `Settings/Deploy keys`). This gives Flux read access to your repository.

### Stage 6: Bootstrap Talos, Kubernetes, and Flux

> [!WARNING]
> It might take a while for the cluster to be setup (10+ minutes is normal). During which time you will see a variety of error messages like: "couldn't get current server API group list," "error: no matching resources found", etc. 'Ready' will remain "False" as no CNI is deployed yet. **This is normal.** If this step gets interrupted, e.g. by pressing <kbd>Ctrl</kbd> + <kbd>C</kbd>, you likely will need to [reset the cluster](#-reset) before trying again

1. Install Talos:

    ```sh
    mise run //bootstrap:talos
    ```

2. Install cilium, coredns, spegel (multi-node clusters), cert-manager, flux and sync the cluster to the repository state:

    ```sh
    mise run //bootstrap:apps
    ```

3. Watch the rollout of your cluster happen:

    ```sh
    kubectl get pods --all-namespaces --watch
    ```

## 📣 Post installation

### ✅ Verifications

1. Check the status of Cilium:

    ```sh
    kubectl -n kube-system exec ds/cilium --container cilium-agent -- cilium status
    ```

2. Check the status of Flux and if the Flux resources are up-to-date and in a ready state:

    📍 _Run `mise run //kubernetes:reconcile` to force Flux to sync your Git repository state_

    ```sh
    flux check
    flux get sources git flux-system
    flux get ks -A
    flux get hr -A
    ```

3. Check TCP connectivity to both the internal and external gateways:

    📍 _The variables are only placeholders, replace them with your actual values_

    ```sh
    nmap -Pn -n -p 443 ${gateways_internal} ${gateways_external} -vv
    ```

4. Check you can resolve DNS for `echo`, this should resolve to `${gateways_external}` (or `${gateways_internal}` when `ingress.mode` is `"none"`):

    📍 _The variables are only placeholders, replace them with your actual values_

    ```sh
    dig @${gateways_dns} echo.${domain_name}
    ```

5. Check the status of your wildcard `Certificate`:

    ```sh
    kubectl -n network describe certificates
    ```

### 🌐 Public DNS

📍 _Only applies when `ingress.mode` is `"cloudflare-tunnel"` or `"direct"`. With `"none"` there is no `envoy-external` gateway or public DNS: `echo` uses `envoy-internal` and resolves only through [Home DNS](#-home-dns), and `flux-webhook` is skipped unless you set `webhook_provider` explicitly (e.g. for a Git host on your LAN)._

> [!TIP]
> Use the `envoy-external` gateway on `HTTPRoutes` to make applications public to the internet. These are also accessible on your private network once you set up split DNS.

With `dns.provider = "cloudflare"`, the `cloudflare-dns` application ([external-dns](https://github.com/kubernetes-sigs/external-dns)) in the `network` namespace will handle creating public DNS records; with `"none"` you create them at your DNS host yourself. By default, `echo` and `flux-webhook` (unless `webhook_provider = "none"`) are the only subdomains reachable from the public internet. In order to make additional applications public you must **set the correct gateway** like in the HelmRelease for `echo`.

### 🏠 Home DNS

> [!TIP]
> Use the `envoy-internal` gateway on `HTTPRoutes` to make applications private to your network. If you're having trouble with internal DNS resolution check out [this](https://github.com/onedr0p/cluster-template/discussions/719) GitHub discussion.

`k8s_gateway` will provide DNS resolution to external Kubernetes resources (i.e. points of entry to the cluster) from any device that uses your home DNS server. For this to work, your home DNS server must be configured to forward DNS queries for `${domain_name}` to `${gateways_dns}` instead of the upstream DNS server(s) it normally uses. This is a form of **split DNS** (aka split-horizon DNS / conditional forwarding).

_... Nothing working? That is expected, this is DNS after all!_

### 🪝 Git Webhook

By default Flux will periodically check your git repository for changes. In-order to have Flux reconcile on `git push` you must configure your Git provider to send `push` events to Flux.

📍 _Don't want a webhook, or your Git provider can't reach the cluster? Set `webhook_provider = "none"` in `cluster.toml` and skip this section; Flux will keep polling on an interval. It already defaults to `"none"` when `ingress.mode` is `"none"` or the wildcard certificate comes from the in-cluster CA._

📍 _For a Git host on your LAN with an internal-only cluster, set `webhook_provider` explicitly. `flux-webhook` is then served on `envoy-internal`: the Git host must resolve it through [Home DNS](#-home-dns), and with `dns.provider = "none"` it must trust the cluster's internal CA. Self-hosted Gitea/Forgejo also need `flux-webhook.<domain>` added to `[webhook] ALLOWED_HOST_LIST`, since private addresses are blocked by default._

1. Obtain the webhook path:

    📍 _Hook id and path should look like `/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123`_

    ```sh
    kubectl -n flux-system get receiver flux-webhook --output=jsonpath='{.status.webhookPath}'
    ```

2. Piece together the full URL with the webhook path appended:

    ```text
    https://flux-webhook.${domain_name}/hook/12ebd1e363c641dc3c2e430ecf3cee2b3c7a5ac9e1234506f6f5f3ce1230e123
    ```

3. Navigate to your repository settings and add a webhook with that URL and the secret token from `flux-webhook-token.txt`:

    - **GitHub**: under "Settings/Webhooks" press the "Add webhook" button. Fill in the webhook URL, paste the token as the secret, Content type: `application/json`, Events: Choose Just the push event, and save.
    - **GitLab**: under "Settings/Webhooks" fill in the webhook URL, paste the token as the secret token, check the push events trigger, and save. Also set `webhook_provider = "gitlab"` in `cluster.toml`.
    - **Gitea/Forgejo**: under "Settings/Webhooks" add a **Gitea/Forgejo** webhook with the webhook URL, method `POST`, content type `application/json`, paste the token as the secret, trigger on push events, and save. Use `webhook_provider = "github"` since these providers emulate GitHub webhooks; set it explicitly on internal-only clusters, where the default is `"none"`.

### 🤖 Renovate

[Renovate](https://www.mend.io/renovate) is a tool that automates dependency management. It is designed to scan your repository around the clock and open PRs for out-of-date dependencies it finds. Common dependencies it can discover are Helm charts, container images, GitHub Actions and more! In most cases merging a PR will cause Flux to apply the update to your cluster.

To enable Renovate on GitHub, click the 'Configure' button over at their [Github app page](https://github.com/apps/renovate) and select your repository. On other Git providers you can [self-host Renovate](https://docs.renovatebot.com/getting-started/running/#self-hosting-renovate); note that fetching the shared preset in `.renovaterc.json5` requires a `GITHUB_COM_TOKEN`. Renovate creates a "Dependency Dashboard" as an issue in your repository, giving an overview of the status of all updates. The dashboard has interactive checkboxes that let you do things like advance scheduling or reattempt update PRs you closed without merging.

The base Renovate configuration in your repository can be viewed at [.renovaterc.json5](.renovaterc.json5). By default it is scheduled to be active with PRs every weekend, but you can [change the schedule to anything you want](https://docs.renovatebot.com/presets-schedule), or remove it if you want Renovate to open PRs immediately.

### 🧹 Tidy up

Once your cluster is fully configured and you no longer need to run `mise run configure`, it's a good idea to clean up the repository by archiving the [template](./template) directory and any files related to the templating process under `.private/` (gitignored). This will help eliminate unnecessary clutter from the upstream template repository and resolve any "duplicate registry" warnings from Renovate.

1. Tidy up your repository:

    ```sh
    mise run //template:tidy
    ```

2. Push your changes to git:

    ```sh
    git add -A
    git commit -m "chore: tidy up :broom:"
    git push
    ```

## 🛠️ Talos and Kubernetes Maintenance

📍 _Run `mise tasks --all` to list every task, including the `//bootstrap`, `//kubernetes` and `//talos` ones._

### ⚙️ Updating Talos node configuration

> [!TIP]
> Ensure you have updated `topf.yaml` and any patches with your updated configuration. In some cases you **not only need to apply the configuration but also upgrade talos** to apply new configuration.

```sh
# Preview the rendered machine configs (optional)
mise run //talos:render
# Apply the config to the node
mise run //talos:apply-node <node>
# e.g. mise run //talos:apply-node k8s-0
```

### 🧩 Adding your own Talos patches

[topf](https://postfinance.github.io/topf/main/configuration-model/) merges every patch it finds in these directories under `talos/`, in this order and alphabetically within each, later patches taking precedence:

- `all/`: every node
- `control-plane/` or `worker/`: nodes with that role
- `node/<hostname>/`: a single node

Files ending in `.yaml` are strategic merge patches, `.yaml.tpl` files are Go templates that can read `data:` from `topf.yaml` (`.Data.<key>`, `.Node.Data.<key>`), SOPS-encrypted files are decrypted automatically and comment-only files are skipped.

> [!IMPORTANT]
> `mise run configure` overwrites the files it renders (including `topf.yaml`) but leaves files you add alone, so give your patches names the template doesn't use, such as a `99-` prefix. After `mise run //template:tidy` nothing is re-rendered.

```yaml
# talos/all/99-local-sysctls.yaml
---
apiVersion: v1alpha1
kind: SysctlConfig
params:
    vm.max_map_count: "262144"
```

`mise run configure` renders every node's config and fails on an invalid patch or machine config. Check the result with `mise run //talos:diff`, then apply it as shown [above](#️-updating-talos-node-configuration).

### ⬆️ Updating Talos and Kubernetes versions

> [!TIP]
> Ensure the `talosVersion` and `kubernetesVersion` in `topf.yaml` are up-to-date with the version you wish to upgrade to.

```sh
# Upgrade talos on a node
mise run //talos:upgrade-node <node>
# e.g. mise run //talos:upgrade-node k8s-0
```

```sh
# Upgrade cluster to a newer Kubernetes version
mise run //talos:upgrade-k8s
```

> [!IMPORTANT]
> After a `kubernetesVersion` bump in `topf.yaml` (e.g. from a Renovate PR), run `mise run //talos:upgrade-k8s` **before** any `//talos:apply` or `//talos:apply-node`. An apply pushes the new version straight into the machine configs without `upgrade-k8s`'s version skew and readiness checks.

### ➕ Adding a node to your cluster

At some point you might want to expand your cluster to run more workloads and/or improve the reliability of your cluster. Keep in mind it is recommended to have an **odd number** of control plane nodes for quorum reasons.

You don't need to re-bootstrap the cluster to add new nodes. Follow these steps:

1. **Prepare the new node**: Review the [Stage 2: Machine Preparation](#stage-2-machine-preparation) section and boot your new node into maintenance mode.

2. **Get the node information**: While the node is in maintenance mode, retrieve the disk and MAC address information needed for configuration:

    ```sh
    talosctl get disks -n <ip> --insecure
    talosctl get links -n <ip> --insecure
    ```

3. **Update the configuration**: Add a `[[nodes]]` entry for the new node to `cluster.toml` (including the disk and MAC address from step 2) and re-render:

    ```sh
    mise run configure
    ```

    After `mise run //template:tidy` there is no `cluster.toml` any more: read the documentation for [topf](https://postfinance.github.io/topf/) and extend `talos/topf.yaml` (and any `node/<hostname>/` patches) manually instead.

4. **Apply the configuration**:

    ```sh
    # Preview the rendered machine configs (optional)
    mise run //talos:render

    # Apply the configuration to the node
    mise run //talos:apply-node <node>
    # e.g. mise run //talos:apply-node k8s-3
    ```

The node should join the cluster automatically and workloads will be scheduled once they report as ready.

### 💾 Backing up etcd

etcd holds the whole cluster state, and with a single control-plane node there is no other copy. Take a snapshot before risky changes:

```sh
mise run //talos:etcd-snapshot
# or write it elsewhere: mise run //talos:etcd-snapshot /path/to/etcd.snapshot
```

Snapshots go to `.private/etcd/` by default, which is not committed. They contain every Kubernetes Secret, encrypted with the key in `talos/secrets.sops.yaml`, so restoring needs that same file. To restore, follow Talos' [disaster recovery guide](https://docs.siderolabs.com/talos/v1.14/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery) (`talosctl bootstrap --recover-from`). Persistent volume data is not included.

### 🔑 Renewing admin credentials

The admin certificates in `talos/talosconfig` and `kubeconfig` expire after a year. Both are signed locally from `talos/secrets.sops.yaml`, so they can be renewed at any time, even after they have expired:

```sh
mise run //talos:talosconfig
mise run //talos:kubeconfig
```

### 💥 Reset

> [!CAUTION]
> **Resetting** the cluster **multiple times in a short period of time** could lead to being **rate limited by DockerHub or Let's Encrypt**.

There might be a situation where you want to destroy your Kubernetes cluster. The following command will reset your nodes back to maintenance mode, after which `mise run //bootstrap:talos` can set the cluster up again.

```sh
mise run //talos:reset
```

To take a single node out of a running cluster, `mise run //talos:reset-node <node>` drains it and removes it from etcd first; add `--force` to skip that for the last control plane node or a broken cluster. Both tasks only wipe the `STATE` and `EPHEMERAL` partitions, so the installed Talos boots back into maintenance mode. Bring a single node back with `mise run //talos:apply-node <node>`; `//bootstrap:talos` is only for a new cluster and refuses to run when the first control plane node was reset but others were not, as that would start a second etcd cluster.

## 🐛 Debugging

Below is a general guide on trying to debug an issue with a resource or application. For example, if a workload/resource is not showing up or a pod has started but in a `CrashLoopBackOff` or `Pending` state. These steps do not include a way to fix the problem as the problem could be one of many different things.

1. Check if the Flux resources are up-to-date and in a ready state:

    📍 _Run `mise run //kubernetes:reconcile` to force Flux to sync your Git repository state_

    ```sh
    flux get sources git -A
    flux get ks -A
    flux get hr -A
    ```

2. Do you see the pod of the workload you are debugging:

    ```sh
    kubectl -n <namespace> get pods -o wide
    ```

3. Check the logs of the pod if it's there:

    ```sh
    kubectl -n <namespace> logs <pod-name> -f
    ```

4. If a resource exists, try to describe it to see what problems it might have:

    ```sh
    kubectl -n <namespace> describe <resource> <name>
    ```

5. Check the namespace events:

    ```sh
    kubectl -n <namespace> get events --sort-by='.metadata.creationTimestamp'
    ```

Resolving problems that you have could take some tweaking of your YAML manifests in order to get things working, other times it could be a external factor like permissions on a NFS server. If you are unable to figure out your problem see the support sections below.

## ❔ What's next

There's a lot to absorb here, especially if you're new to these tools, so take time to learn how the components fit together and read their documentation. This shouldn't be a production environment yet: experiment, break things intentionally, and challenge yourself to fix them. Below are some optional considerations you may want to explore.

### Applications

When you add an application, copy an existing `ks.yaml` such as `kubernetes/apps/default/echo/ks.yaml`. Each Flux `Kustomization` must set `spec.patches`, even as `patches: []`, because Flux adds the `HelmRelease` defaults to this list. If one `Kustomization` omits it, the `flux-system` Kustomization fails to build and Flux does not apply changes under `kubernetes/apps`. The error is `add operation does not apply: doc is missing path: "/spec/patches/0": missing value`.

### DNS

The template uses [k8s_gateway](https://github.com/k8s-gateway/k8s_gateway) to serve DNS for your applications from inside the cluster. To offload that to your router or another device, consider [external-dns](https://github.com/kubernetes-sigs/external-dns) (which the template already uses for Cloudflare) with a home DNS provider such as:

- [Pi-hole](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/pihole.md)
- [UniFi](https://github.com/kashalls/external-dns-unifi-webhook)
- [Adguard Home](https://github.com/muhlba91/external-dns-provider-adguard)
- [Bind](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/rfc2136.md)

### Secrets

SOPS is an excellent tool for managing secrets in a GitOps workflow. However, it can become cumbersome when rotating secrets or maintaining a single source of truth for secret items.

For a more streamlined approach to those issues, consider [External Secrets](https://external-secrets.io/latest/). This tool allows you to move away from SOPS and leverage an external provider for managing your secrets. External Secrets supports a wide range of providers, from cloud-based solutions to self-hosted options.

### Storage

If your workloads require persistent storage with features like replication or connectivity to NFS, SMB, or iSCSI servers, there are several projects worth exploring:

- [rook-ceph](https://github.com/rook/rook) / [longhorn](https://github.com/longhorn/longhorn) / [openebs](https://github.com/openebs/openebs)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)
- [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) / [csi-driver-smb](https://github.com/kubernetes-csi/csi-driver-smb)
- [synology-csi](https://github.com/SynologyOpenSource/synology-csi)
- [truenas-csi](https://github.com/truenas/truenas-csi) / [tns-csi](https://github.com/fenio/tns-csi)

### Community Repositories

Community member [@whazor](https://github.com/whazor) created [Kubesearch](https://kubesearch.dev) to allow searching Flux HelmReleases across Github and Gitlab repositories with the `kubesearch` topic.

## 🙋 Support

- Make a post in this repository's GitHub [Discussions](https://github.com/onedr0p/cluster-template/discussions).
- Start a thread in the `#support` or `#cluster-template` channels in the [Home Operations](https://discord.gg/home-operations) Discord server.

## 📺 Media

Check out these videos below. If you find them helpful, a like and subscribe goes a long way!

<a href="https://youtube.com/watch?v=aeUKOpeoiUs">
  <img src="https://github.com/user-attachments/assets/2dab1c6f-7b27-4b94-a7ad-a6d9c5b17c78" alt="Youtube Video" width="300">
</a>
&nbsp;&nbsp;
<a href="https://youtube.com/watch?v=hoi2GzvJUXM">
  <img src="https://github.com/user-attachments/assets/5b939b90-0019-4515-b90c-321ffe7448cf" alt="Youtube Video" width="300">
</a>

## 🙌 Related Projects

If this repo is too hot to handle or too cold to hold check out these following projects.

- [ajaykumar4/cluster-template](https://github.com/ajaykumar4/cluster-template) - _A template for deploying a Talos Kubernetes cluster including Argo for GitOps_
- [mitchross/k3s-argocd-starter](https://github.com/mitchross/k3s-argocd-starter) - starter kit for k3s, argocd
- [ricsanfre/pi-cluster](https://github.com/ricsanfre/pi-cluster) - _Pi Kubernetes Cluster. Homelab kubernetes cluster automated with Ansible and FluxCD_
- [techno-tim/k3s-ansible](https://github.com/techno-tim/k3s-ansible) - _The easiest way to bootstrap a self-hosted High Availability Kubernetes cluster. A fully automated HA k3s etcd install with kube-vip, MetalLB, and more. Build. Destroy. Repeat._

## 🤝 Thanks

Big shout out to all the contributors, sponsors and everyone else who has helped on this project.
