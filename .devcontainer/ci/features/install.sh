#!/bin/sh

ARCH="$(uname -m)"
if [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" == "aarch64" ]; then
    ARCH="arm64"
fi

#
# Install Tools from the Alpine Repositories
#

apk add --no-cache \
    bash bind-tools ca-certificates curl python3 \
    py3-pip moreutils jq git \
    openssh-client

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
    age direnv fish github-cli \
    go-task helm k0sctl kubectl \
    kustomize sops yq

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    cilium-cli flux stern

# Naming things is hard
ln -s /usr/bin/go-task /usr/local/bin/task

#
# Install Tools not in Alpine Repositories
#

curl https://i.jpillora.com/cloudflare/cloudflared! | sudo bash
curl https://i.jpillora.com/budimanjojo/talhelper! | sudo bash
curl https://i.jpillora.com/yannh/kubeconform! | sudo bash

curl -fsSL -o /usr/local/bin/talosctl \
    "https://github.com/siderolabs/talos/releases/latest/download/talosctl-linux-${ARCH}"
chmod +x /usr/local/bin/talosctl
