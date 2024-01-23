#!/usr/bin/env bash

# Hook direnv into fish
cat << EOF > ~/.config/fish/conf.d/direnv.fish
direnv hook fish | source
EOF

# Hook starship into fish
cat << EOF > ~/.config/fish/conf.d/starship.fish
starship init fish | source
EOF

# Export the direnv environment variables
task workstation:direnv

# Remove the .venv directory
rm -rf .venv

# Create a new virtual environment
task workstation:venv
