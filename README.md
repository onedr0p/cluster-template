# Template for deploying k3s and Flux backed by SOPS secrets

Template for creating a [k3s](https://k3s.io/) cluster with [k3sup](https://github.com/alexellis/k3sup).

Using this template you will be able to bootstrap the nodes you want with the following components:

- [k3s](https://k3s.io/)
- [flannel](https://github.com/flannel-io/flannel)
- [local-path-provisioner](https://github.com/rancher/local-path-provisioner)
- [flux](https://toolkit.fluxcd.io/)
- [metallb](https://metallb.universe.tf/)
- [cert-manager](https://cert-manager.io/) with Cloudflare DNS challenge

## :memo:&nbsp; Prerequisites

### :computer:&nbsp; Nodes

Bare metal or VMs with any modern operating system like Ubuntu, Debian or CentOS.

### :wrench:&nbsp; Tools

| Tool                                                               | Purpose                                                             | Required |
|--------------------------------------------------------------------|---------------------------------------------------------------------|:--------:|
| [k3sup](https://github.com/alexellis/k3sup)                        | Tool to install k3s on your nodes                                   |    ✅     |
| [flux](https://toolkit.fluxcd.io/)                                 | Operator that manages your k8s cluster based on your Git repository |    ✅     |
| [kustomize](https://kustomize.io/)                                 | Template-free way to customize application configuration            |    ✅     |
| [SOPS](https://github.com/mozilla/sops)                            | Encrypts k8s secrets with GnuPG                                     |    ✅     |
| [GnuPG](https://gnupg.org/)                                        | Encrypts and signs your data                                        |    ✅     |
| [pinentry](https://gnupg.org/related_software/pinentry/index.html) | Allows GnuPG to read passphrases and PIN numbers                    |    ✅     |
| [direnv](https://github.com/direnv/direnv)                         | Exports env vars based on present working directory                 |    ❌     |
| [pre-commit](https://github.com/pre-commit/pre-commit)             | Keeps formatting consistency across your files                      |    ❌     |

## :rocket:&nbsp; Installation

Very first step will be to create a new repository by clicking the **Use this template** button on this page.

### :key:&nbsp; Setting up GnuPG keys

1. Create a Personal GPG Key, password protected, and export the fingerprint

```sh
export GPG_TTY=$(tty)
export PERONAL_KEY_NAME="First name Last name (location) <email>"

gpg --batch --full-generate-key <<EOF
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Real: ${PERONAL_KEY_NAME}
EOF

gpg --list-secret-keys "${PERONAL_KEY_NAME}"
# pub   rsa4096 2021-03-11 [SC]
#       772154FFF783DE317KLCA0EC77149AC618D75581
# uid           [ultimate] k8s@home (Macbook) <k8s-at-home@gmail.com>
# sub   rsa4096 2021-03-11 [E]

export PERSONAL_KEY_FP=772154FFF783DE317KLCA0EC77149AC618D75581
```

2. Create a Flux GPG Key and export the fingerprint

```sh
export GPG_TTY=$(tty)
export FLUX_KEY_NAME="Cluster name (Flux) <email>"

gpg --batch --full-generate-key <<EOF
%no-protection
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Real: ${KEY_NAME}
EOF

gpg --list-secret-keys "${FLUX_KEY_NAME}"
# pub   rsa4096 2021-03-11 [SC]
#       AB675CE4CC64251G3S9AE1DAA88ARRTY2C009E2D
# uid           [ultimate] Home cluster (Flux) <k8s-at-home@gmail.com>
# sub   rsa4096 2021-03-11 [E]

export FLUX_KEY_FP=AB675CE4CC64251G3S9AE1DAA88ARRTY2C009E2D
```

### :sailboat:&nbsp; Installing k3s with k3sup

1. Ensure you are able to SSH into you nodes with using your private ssh key. This is how k3sup is able to connect to your remote node.

2. Install the master node

```sh
k3sup install \
    --host=169.254.1.1 \
    --user=k8s-at-home \
    --k3s-version=v1.20.5+k3s1 \
    --k3s-extra-args="--disable servicelb --disable traefik"
```

3. Join a worker node(s) (optional)

```sh
k3sup join \
    --host=169.254.1.2 \
    --server-host=169.254.1.1 \
    --k3s-version=v1.20.5+k3s1 \
    --user=k8s-at-home
```

4. Verify nodes are online
   
```sh
kubectl --kubeconfig=./kubeconfig get nodes
# NAME           STATUS   ROLES                       AGE     VERSION
# k8s-master-a   Ready    control-plane,master      4d20h   v1.20.5+k3s1
# k8s-worker-a   Ready    worker                    4d20h   v1.20.5+k3s1
```

### GitOps with Flux

1. Pre-create the namespace
   
```sh
kubectl --kubeconfig=./kubeconfig create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
```

1. Add the Flux GPG key in-order for Flux to decrypt SOPS secrets

```sh
gpg --export-secret-keys --armor "${FLUX_KEY_FP}" |
kubectl --kubeconfig=./kubeconfig create secret generic sops-gpg \
    --namespace=flux-system \
    --from-file=sops.asc=/dev/stdin
```

3. Update files using `envsubst` or by updating the files listed below manually

```sh
export BOOTSTRAP_GITHUB_REPOSITORY="k8s-at-home/home-cluster"
export BOOTSTRAP_METALLB_LB_RANGE="169.254.1.10-169.254.1.20"
export BOOTSTRAP_DOMAIN="k8s-at-home.com"
export BOOTSTRAP_DOMAIN_CERT="k8s-at-home"
export BOOTSTRAP_CLOUDFLARE_TOKEN="dsKq41iLAbXE37GV"

envsubst < ./.sops.yaml
envsubst < ./cluster/cluster-secrets.yaml
envsubst < ./cluster/cluster-settings.yaml
envsubst < ./cluster/base/flux-system/gotk-sync.yaml
envsubst < ./cluster/core/infrastructure/cert-manager/secret.enc.yaml
```

4. **Verify** all the above files have the correct information present

5. Encrypt `cluster/cluster-secrets.yaml` and `cert-manager/secret.enc.yaml` with SOPS

```sh
export GPG_TTY=$(tty)
sops --encrypt --in-place ./cluster/base/cluster-secrets.yaml
sops --encrypt --in-place ./cluster/core/infrastructure/cert-manager/secret.enc.yaml
```

Variables defined in `cluster-secrets.yaml` and `cluster-settings.yaml` will be usable anywhere in your yaml manifests.

6. **Verify** all the above files are **encrypted** with SOPS

7. Push you changes to git

```sh
git add -A
git commit -m "initial commit"
git push
```

8. Install Flux

```sh
kubectl --kubeconfig=./kubeconfig --kustomize=./cluster/base/flux-system
```

## Post installation

### pre-commit

```sh
pre-commit install-hooks
```

## What's next?

The world is your oyster, try installing a ingress controller!

## :handshake:&nbsp; Thanks

Big shout out to all the authors and contributors to the projects that we are using in this repository.