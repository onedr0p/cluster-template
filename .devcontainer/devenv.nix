{ pkgs, ... }:

{
  packages = with pkgs; [
    age
    ansible
    fluxcd
    cloudflared
    cilium-cli
    direnv
    go-task
    ipcalc
    jq
    kubectl
    # devenv.sh also offers pre-commit, but does not integrate with existing precommit file
    pre-commit
    sops
    yq-go
    # recommended
    kubernetes-helm
    kustomize
    stern
    yamllint
    # generic system tools
    curl
    dig
    fd
    fzf
    iproute2
    k9s
    pwgen
    socat
    tcpdump
    vgrep
    wget

  ];

  devcontainer.enable = true;

  # pre-commit.hooks.yamllint.enable = true;
  # pre-commit.settings.yamllint.configPath = "$DEVENV_ROOT/.yamllint.yaml";
}
