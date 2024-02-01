# Setup Local Workstation

You have two different options for setting up your local workstation. The first option is a standard method of setting up the CLI tools directly on your workstation. The second option is using a [devcontainer](https://containers.dev/) which requires you to have [Docker](https://www.docker.com/products/docker-desktop/) and [VSCode](https://code.visualstudio.com/) installed. This method is the fastest to get going because all the required CLI tools are provided for you in my [devcontainer](https://github.com/onedr0p/cluster-template/pkgs/container/cluster-template%2Fdevcontainer) image.

## Standard

1. Install the most recent version of [task](https://taskfile.dev/), see the [installation docs](https://taskfile.dev/installation/) for other supported platforms.

    ```sh
    # Homebrew
    brew install go-task
    # or, Arch
    pacman -S --noconfirm go-task && ln -sf /usr/bin/go-task /usr/local/bin/task
    ```

2. Install the most recent version of [direnv](https://direnv.net/), see the [installation docs](https://direnv.net/docs/installation.html) for other supported platforms.

    ```sh
    # Homebrew
    brew install direnv
    # or, Arch
    pacman -S --noconfirm direnv
    ```

    📍 _After `direnv` is installed be sure to **[hook it into your preferred shell](https://direnv.net/docs/hook.html)** and then run `task workstation:direnv`_

3. Install the additional **required** CLI tools

   📍 _**Not using Homebrew or ArchLinux?** Try using the generic Linux task below, if that fails check out the [Brewfile](.taskfiles/Workstation/Brewfile)/[Archfile](.taskfiles/Workstation/Archfile) for what CLI tools needed and install them._

    ```sh
    # Homebrew
    task workstation:brew
    # or, Arch with yay/paru
    task workstation:arch
    # or, Generic Linux (YMMV, this pulls binaires in to ./bin)
    task workstation:generic-linux
    ```

4. Setup a Python virual environment by running the following task command.

    📍 _This commands requires Python 3.11+ to be installed._

    ```sh
    task workstation:venv
    ```

## Devcontainer

Start Docker and open your repository in VSCode. There will be a pop-up asking you to use the `devcontainer`, click the button to start using it.
