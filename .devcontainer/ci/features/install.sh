#!/usr/bin/env bash
set -e
set -o noglob

apk add --no-cache \
    bash bind-tools ca-certificates curl fish fzf gettext git \
    iputils mise moreutils openssh-client openssl starship

# Create the fish configuration directory
mkdir -p /home/vscode/.config/fish/{completions,conf.d}

# Add hooks into fish
tee /home/vscode/.config/fish/conf.d/hooks.fish > /dev/null <<EOF
if status is-interactive
    mise activate fish | source
    starship init fish | source
end
EOF

# Add aliases into fish
tee /home/vscode/.config/fish/conf.d/aliases.fish > /dev/null <<EOF
alias kubectl kubecolor
alias k kubectl
EOF

# Custom fish prompt
tee /home/vscode/.config/fish/conf.d/fish_greeting.fish > /dev/null <<EOF
set fish_greeting
EOF

# Set ownership vscode .config directory to the vscode user
chown -R vscode:vscode /home/vscode/.config
