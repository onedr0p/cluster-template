#!/usr/bin/env bash
set -e
set -o noglob

apk add --no-cache \
    bash bind-tools ca-certificates curl python3 \
    py3-pip moreutils jq git iputils openssh-client \
    starship fzf fish

apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community \
        age helm kubectl sops

sudo apk add --no-cache \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
        lsd

for app in \
    "budimanjojo/talhelper!" \
    "cilium/cilium-cli!!?as=cilium&type=script" \
    "cli/cli!!?as=gh&type=script" \
    "cloudflare/cloudflared!!?as=cloudflared&type=script" \
    "derailed/k9s!!?as=k9s&type=script" \
    "direnv/direnv!!?as=direnv&type=script" \
    "fluxcd/flux2!!?as=flux&type=script" \
    "go-task/task!!?as=task&type=script" \
    "helmfile/helmfile!!?as=helmfile&type=script" \
    "kubecolor/kubecolor!!?as=kubecolor&type=script" \
    "kubernetes-sigs/krew!!?as=krew&type=script" \
    "kubernetes-sigs/kustomize!!?as=kustomize&type=script" \
    "stern/stern!!?as=stern&type=script" \
    "siderolabs/talos!!?as=talosctl&type=script" \
    "yannh/kubeconform!!?as=kubeconform&type=script" \
    "mikefarah/yq!!?as=yq&type=script"
do
    echo "=== Installing ${app} ==="
    curl -fsSL "https://i.jpillora.com/${app}" | bash
done

# Create the fish configuration directory
mkdir -p /home/vscode/.config/fish/{completions,conf.d}

# Setup autocompletions for fish
for tool in cilium flux helm helmfile k9s kubectl kustomize talhelper talosctl; do
    $tool completion fish > /home/vscode/.config/fish/completions/$tool.fish
done
gh completion --shell fish > /home/vscode/.config/fish/completions/gh.fish
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
