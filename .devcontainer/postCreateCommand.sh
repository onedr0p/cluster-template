#!/usr/bin/env bash
set -e
set -o noglob

# Create the fish configuration directory
mkdir -p ~/.config/fish/{completions,conf.d}

# Hook direnv into fish
tee ~/.config/fish/conf.d/direnv.fish > /dev/null <<EOF
direnv hook fish | source
EOF

# Hook starship into fish
tee ~/.config/fish/conf.d/starship.fish > /dev/null <<EOF
starship init fish | source
EOF

# Silence fish prompt
tee ~/.config/fish/conf.d/fish_greeting.fish > /dev/null <<EOF
function fish_greeting
    echo (set_color yellow)"Press [enter] to clear the direnv error"
end
EOF

# Setup fisher plugin manager for fish
/usr/bin/fish -c "curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher"
/usr/bin/fish -c "fisher install decors/fish-colored-man"
/usr/bin/fish -c "fisher install edc/bass"
/usr/bin/fish -c "fisher install jorgebucaran/autopair.fish"
/usr/bin/fish -c "fisher install nickeb96/puffer-fish"

# Setup CLI tools autocompletions for fish
for tool in cilium flux helm k9s kubectl kustomize talhelper talosctl; do
    $tool completion fish > ~/.config/fish/completions/$tool.fish
done
gh completion --shell fish > ~/.config/fish/completions/gh.fish
k0sctl completion --shell fish > ~/.config/fish/completions/k0sctl.fish
stern --completion fish > ~/.config/fish/completions/stern.fish
yq shell-completion fish > ~/.config/fish/completions/yq.fish

# Create/update virtual environment
if ! grep -q "venv /workspaces/" .venv/pyvenv.cfg; then
    rm -rf .venv
fi
task workstation:venv

# Export the direnv environment variables
task workstation:direnv
