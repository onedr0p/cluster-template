sudo apt update -y
sudo apt install -y software-properties-common \
    direnv \
    age \
    ipcalc \
    jq \
    gnupg \
    curl \
    apt-transport-https \
    ca-certificates \
    golang \
    python3-is-python

# Golang
echo 'GOPATH=~/go' >> ~/.bashrc
source ~/.bashrc
mkdir $GOPATH
echo 'PATH="$GOPATH/bin:$PATH"' >> ~/.bashrc


# NodeJS LTS
sudo curl -s https://deb.nodesource.com/setup_16.x | sudo bash
curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y nodejs yarn

# Ansible
pip install ansible

# Flux
curl -s https://fluxcd.io/install.sh | sudo bash
echo '. <(flux completion bash)' >> ~/.bashrc

# kubectl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubectl
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# SOPS
go install go.mozilla.org/sops/cmd/sops@latest

# Go Task
go install github.com/go-task/task/v3/cmd/task@latest

# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository --yes --update "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt install -y terraform
terraform -install-autocomplete

# Helm
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update && sudo apt install -y helm

# Kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash

# Pre-commit
pip install pre-commit

# Gitleaks
go install github.com/zricethezav/gitleaks@latest

# Prettier
yarn global add prettier
