# cluster-k3s

Template for creating a k3s cluster with [k3sup](https://github.com/alexellis/k3sup), [Flux](https://toolkit.fluxcd.io/) and [SOPS](https://github.com/mozilla/sops)

This template will bootstrap the nodes you want with the following components

- k3s
- flux
- metallb
- flannel

## :memo:&nbsp; Prerequisites

### :computer:&nbsp; Nodes

Bare metal or VMs with a modern operating system like Ubuntu, Debian or CentOS.

### :wrench:&nbsp; Tools

| Tool                                                   | Purpose                                                             | Required |
|--------------------------------------------------------|---------------------------------------------------------------------|:--------:|
| [k3sup](https://github.com/alexellis/k3sup)            | Tool to install k3s on your nodes                                   |    ✅     |
| [flux](https://toolkit.fluxcd.io/)                     | Operator that manages your k8s cluster based on your Git repository |    ✅     |
| [SOPS](https://github.com/mozilla/sops)                | Encrypts k8s secrets with GnuPG                                     |    ✅     |
| [GnuPG](https://gnupg.org/)                            | Encrypts and signs your data                                        |    ✅     |
| [direnv](https://github.com/direnv/direnv)             | Exports env vars based on present working directory                 |    ❌     |
| [pre-commit](https://github.com/pre-commit/pre-commit) | Keeps formatting consistency across your files                      |    ❌     |

## :rocket:&nbsp; Installation

### :sailboat:&nbsp; k3sup

Bootstrap your nodes with k3s using k3sup

## :handshake:&nbsp; Thanks

A lot of inspiration for my cluster came from the people that have shared their clusters over at [awesome-home-kubernetes](https://github.com/k8s-at-home/awesome-home-kubernetes)