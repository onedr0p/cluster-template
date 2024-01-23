#!/usr/bin/env bash

# Export the direnv environment variables
task workstation:direnv

# Remove the .venv directory
rm -rf .venv

# Create a new virtual environment
task workstation:venv
