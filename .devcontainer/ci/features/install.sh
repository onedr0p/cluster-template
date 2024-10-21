#!/usr/bin/env bash
set -e
set -o noglob

apk add --no-cache \
    age bash bind-tools ca-certificates curl direnv fish fzf \
    gettext git github-cli helm iputils jq k9s python3 py3-pip \
    moreutils openssh-client openssl starship yq

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        flux kubectl kustomize go-task sops

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        cloudflared cilium-cli helmfile kubeconform kubectl-krew lsd stern

for app in \
    "budimanjojo/talhelper!!?as=talhelper&type=script" \
    "kubecolor/kubecolor!!?as=kubecolor&type=script" \
    "siderolabs/talos!!?as=talosctl&type=script"
do
    echo "=== Installing ${app} ==="
    curl -fsSL "https://i.jpillora.com/${app}" | bash
done

# Create the fish configuration directory
mkdir -p /home/vscode/.config/fish/{completions,conf.d}

# Setup autocompletions for fish
gh completion --shell fish > /home/vscode/.config/fish/completions/gh.fish
kubectl completion fish > /home/vscode/.config/fish/completions/kubectl.fish
talhelper completion fish > /home/vscode/.config/fish/completions/talhelper.fish
talosctl completion fish > /home/vscode/.config/fish/completions/talosctl.fish

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
alias task go-task
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
