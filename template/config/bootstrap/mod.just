set no-exit-message
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']
set default-list

kubernetes_dir := justfile_dir() + '/kubernetes'

[doc('Bootstrap the Talos cluster')]
[group('bootstrap')]
talos: talos-secret talos-apply talos-talosconfig talos-kubeconfig

[doc('Bootstrap apps into the Talos cluster')]
[group('bootstrap')]
apps: apps-ready apps-namespaces apps-secrets apps-crds apps-helm
    just log info "Cluster is bootstrapped — Flux will start syncing the Git repository"

[private]
[script]
[working-directory('../talos')]
talos-secret:
    just log info "Generating secrets"
    if [ ! -f secrets.sops.yaml ]; then
        topf secrets --confirm=false | sops --filename-override secrets.sops.yaml --encrypt /dev/stdin > secrets.sops.yaml
    fi

[private]
[working-directory('../talos')]
talos-apply:
    just log info "Applying talos config and bootstrapping"
    topf apply --auto-bootstrap --confirm=false

[private]
[working-directory('../talos')]
talos-talosconfig:
    just log info "Generating talosconfig"
    topf talosconfig > talosconfig

# topf issues short-lived admin certs by default; match the previous
# long-lived kubeconfig behaviour.
[private]
[working-directory('../talos')]
talos-kubeconfig:
    just log info "Fetching kubeconfig"
    topf kubeconfig --validity 8760h > "{{ justfile_dir() }}/kubeconfig"

[private]
[script]
apps-crds:
    just log info "Applying CRDs"
    if ! helmfile --file "{{ source_directory() }}/helmfile/crds.yaml" template --quiet | yq eval-all --exit-status 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts --filename -; then
        just log fatal "Failed to apply crds"
    fi

[private]
[script]
apps-helm:
    just log info "Syncing helmfile"
    if ! helmfile --file "{{ source_directory() }}/helmfile/apps.yaml" sync --hide-notes; then
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
        "{{ source_directory() }}/deploy-key.sops.yaml" \
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
