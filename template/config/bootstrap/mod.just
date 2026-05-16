set no-exit-message
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

kubernetes_dir := justfile_dir() + '/kubernetes'

[private]
default:
    just bootstrap -l

[doc('Bootstrap the Talos cluster')]
[group('bootstrap')]
talos: talos-secret talos-config talos-apply talos-bootstrap talos-kubeconfig

[doc('Bootstrap apps into the Talos cluster')]
[group('bootstrap')]
apps: apps-ready apps-namespaces apps-secrets apps-crds apps-helm
    just log info "Cluster is bootstrapped — Flux will start syncing the Git repository"

[private]
[script]
[working-directory('../talos')]
talos-secret:
    just log info "Generating talsecret"
    if [ ! -f talsecret.sops.yaml ]; then
        talhelper gensecret | sops --filename-override talsecret.sops.yaml --encrypt /dev/stdin > talsecret.sops.yaml
    fi

[private]
[working-directory('../talos')]
talos-config:
    just log info "Generating talos config"
    talhelper genconfig

[private]
[working-directory('../talos')]
talos-apply:
    just log info "Applying talos config"
    talhelper gencommand apply --extra-flags="--insecure" | bash

[private]
[working-directory('../talos')]
talos-bootstrap:
    just log info "Bootstrapping talos"
    until talhelper gencommand bootstrap | bash; do sleep 10; done

[private]
[working-directory('../talos')]
talos-kubeconfig:
    just log info "Fetching kubeconfig"
    until talhelper gencommand kubeconfig --extra-flags="{{ justfile_dir() }} --force" | bash; do sleep 10; done

[private]
[script]
apps-crds:
    just log info "Applying CRDs"
    if ! helmfile --file "{{ source_directory() }}/helmfile.d/00-crds.yaml" template --quiet | yq eval-all --exit-status 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts --filename -; then
        just log fatal "Failed to apply crds"
    fi

[private]
[script]
apps-helm:
    just log info "Syncing helmfile"
    if ! helmfile --file "{{ source_directory() }}/helmfile.d/01-apps.yaml" sync --hide-notes; then
        just log fatal "Failed to sync helmfile"
    fi

[private]
[script]
apps-namespaces:
    just log info "Applying namespaces for apps"
    for app in "{{ kubernetes_dir }}/apps"/*/; do
        ns="$(basename "$app")"
        if kubectl get namespace "$ns" &>/dev/null; then
            just log info "Namespace already exists" namespace "$ns"
        elif kubectl create namespace "$ns" --dry-run=client -o yaml \
                | kubectl apply --server-side --filename - &>/dev/null; then
            just log info "Namespace applied" namespace "$ns"
        else
            just log fatal "Failed to apply namespace" namespace "$ns"
        fi
    done

[private]
[script]
apps-secrets:
    just log info "Applying secrets for apps"
    for secret in \
        "{{ source_directory() }}/github-deploy-key.sops.yaml" \
        "{{ source_directory() }}/sops-age.sops.yaml" \
        "{{ kubernetes_dir }}/components/sops/cluster-secrets.sops.yaml"
    do
        name="$(basename "$secret" .sops.yaml)"
        if sops exec-file "$secret" \
                "kubectl --namespace flux-system apply --server-side --filename {}" &>/dev/null; then
            just log info "Secret applied" resource "$name"
        else
            just log fatal "Failed to apply secret" resource "$name"
        fi
    done

# Wait until nodes register as Ready=False. They only become Ready=True once the CNI is healthy.
[private]
[script]
apps-ready:
    just log info "Waiting for nodes to register as Ready=False"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
            just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..."
            sleep 5
        done
    fi
