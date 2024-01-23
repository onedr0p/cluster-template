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
            openssh-client

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        age direnv fish helm kubectl kustomize sops yq

#
# Install Tools not in Alpine Repositories
#

curl -fsSL "https://i.jpillora.com/budimanjojo/talhelper!" | bash
curl -fsSL "https://i.jpillora.com/cilium/cilium-cli!!?as=cilium" | bash
curl -fsSL "https://i.jpillora.com/cli/cli!!?as=gh" | bash
curl -fsSL "https://i.jpillora.com/cloudflare/cloudflared!" | bash
curl -fsSL "https://i.jpillora.com/fluxcd/flux2!!?as=flux" | bash
curl -fsSL "https://i.jpillora.com/go-task/task!" | bash
curl -fsSL "https://i.jpillora.com/k0sproject/k0sctl!" | bash
curl -fsSL "https://i.jpillora.com/stern/stern!" | bash
curl -fsSL "https://i.jpillora.com/yannh/kubeconform!" | bash

curl -fsSL -o /usr/local/bin/talosctl \
    "https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-${ARCH}"
chmod +x /usr/local/bin/talosctl
