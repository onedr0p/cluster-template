# Create a Git repository

1. Let us start by installing Git on your local workstation. This can be done with mostly any package manager, see [this guide](https://github.com/git-guides/install-git) if you need any help.

2. Create a new public or private repository by clicking [this](https://github.com/new?template_name=cluster-template&template_owner=onedr0p) link to create a new repository under your GitHub account from this template, you may also choose to [fork](https://github.com/onedr0p/cluster-template/fork) it instead.

3. Next you will want to clone **your** shiney new repository to your **local workstation** using git:

    ```sh
    git clone git@github.com:$user/$repository.git
    cd $repository
    ```
