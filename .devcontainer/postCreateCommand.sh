#!/usr/bin/env bash

# Hook direnv into zsh
if [[ -f "/home/vscode/.zshrc" ]]; then
    # shellcheck disable=SC2016
    echo -e 'eval "$(direnv hook zsh)"' >> /home/vscode/.zshrc
fi

# Export the direnv environment variables
task workstation:direnv

# Remove the .venv directory
rm -rf .venv

# Create a new virtual environment
task workstation:venv
