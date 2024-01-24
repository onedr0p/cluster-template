#!/usr/bin/env bash
set -e
set -o noglob

apk add --no-cache \
    bash bind-tools ca-certificates curl python3 \
        py3-pip moreutils jq git iputils \
            openssh-client starship fzf

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        age direnv fish helm kubectl kustomize sops

sudo apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        lsd

for installer_path in \
    "budimanjojo/talhelper!" \
    "cilium/cilium-cli!!?as=cilium" \
    "cli/cli!!?as=gh" \
    "cloudflare/cloudflared!" \
    "derailed/k9s!" \
    "fluxcd/flux2!!?as=flux" \
    "go-task/task!" \
    "k0sproject/k0sctl!" \
    "kubecolor/kubecolor!" \
    "stern/stern!" \
    "siderolabs/talos!!?as=talosctl" \
    "yannh/kubeconform!" \
    "mikefarah/yq!"
do
    curl -fsSL "https://i.jpillora.com/${installer_path}" | bash
done

# Create the fish configuration directory
mkdir -p /home/vscode/.config/fish/{completions,conf.d}

# Setup autocompletions for fish
for tool in cilium flux helm k9s kubectl kustomize talhelper talosctl; do
    $tool completion fish > /home/vscode/.config/fish/completions/$tool.fish
done
gh completion --shell fish > /home/vscode/.config/fish/completions/gh.fish
k0sctl completion --shell fish > /home/vscode/.config/fish/completions/k0sctl.fish
stern --completion fish > /home/vscode/.config/fish/completions/stern.fish
yq shell-completion fish > /home/vscode/.config/fish/completions/yq.fish

# Add hooks into fish
tee /home/vscode/.config/fish/conf.d/hooks.fish > /dev/null <<EOF
if status is-interactive
    direnv hook fish | source
    starship init fish | source
end
EOF

# Add aliases into fish
tee /home/vscode/.config/fish/conf.d/aliases.fish > /dev/null <<EOF
alias ls lsd
alias kubectl kubecolor
alias k kubectl
EOF

# Custom fish prompt
tee /home/vscode/.config/fish/conf.d/fish_greeting.fish > /dev/null <<EOF
set fish_greeting
EOF

# Add direnv whitelist for the workspace directory
mkdir -p /home/vscode/.config/direnv
tee /home/vscode/.config/direnv/direnv.toml > /dev/null <<EOF
[whitelist]
prefix = [ "/workspaces" ]
EOF

# Set ownership vscode .config directory to the vscode user
chown -R vscode:vscode /home/vscode/.config
