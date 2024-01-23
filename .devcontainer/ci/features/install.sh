#!/bin/sh
set -e
set -o noglob

ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
fi

#
# Install Tools from the Alpine Repositories
#

apk add --no-cache \
    bash bind-tools ca-certificates curl python3 \
        py3-pip moreutils jq git iputils \
            openssh-client starship

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        age direnv fish helm kubectl kustomize sops yq

#
# Install Tools not in Alpine Repositories
#

for installer_path in \
    "budimanjojo/talhelper!" \
    "cilium/cilium-cli!!?as=cilium" \
    "cli/cli!!?as=gh" \
    "cloudflare/cloudflared!" \
    "fluxcd/flux2!!?as=flux" \
    "go-task/task!" \
    "k0sproject/k0sctl!" \
    "derailed/k9s!" \
    "stern/stern!" \
    "siderolabs/talos!!?as=talosctl" \
    "yannh/kubeconform!"
do
    curl -fsSL "https://i.jpillora.com/${installer_path}" | bash
done
