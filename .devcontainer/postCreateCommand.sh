#!/usr/bin/env bash
set -e
set -o noglob

# Create the fish configuration directory
mkdir -p ~/.config/fish/conf.d

# Hook direnv into fish
tee ~/.config/fish/conf.d/direnv.fish > /dev/null <<EOF
direnv hook fish | source
EOF

# Hook starship into fish
tee ~/.config/fish/conf.d/starship.fish > /dev/null <<EOF
starship init fish | source
EOF

# Export the direnv environment variables
task workstation:direnv

# Remove the .venv directory
rm -rf .venv

# Create a new virtual environment
task workstation:venv
