set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set unstable
set script-interpreter := ['bash', '-euo', 'pipefail']

bootstrap_dir  := justfile_dir() + '/bootstrap'
kubernetes_dir := justfile_dir() + '/kubernetes'
talos_dir      := justfile_dir() + '/talos'

[private]
default:
    just bootstrap -l

[doc('Bootstrap apps into the Talos cluster (waits, namespaces, secrets, CRDs, helm sync)')]
[group('bootstrap')]
apps: apps-preconditions apps-wait-nodes apps-namespaces apps-secrets apps-crds apps-helm
    just log info "Cluster is bootstrapped — Flux will start syncing the Git repository"

[doc('Bootstrap the Talos cluster (gensecret, genconfig, apply, bootstrap, kubeconfig)')]
[group('bootstrap')]
[script]
[working-directory('../talos')]
talos:
    test -f "{{ justfile_dir() }}/.sops.yaml"
    test -f "$SOPS_AGE_KEY_FILE"
    test -f talconfig.yaml
    if [ ! -f talsecret.sops.yaml ]; then
        just log info "Generating talsecret"
        talhelper gensecret \
            | sops --filename-override talos/talsecret.sops.yaml --encrypt /dev/stdin \
            > talsecret.sops.yaml
    fi
    just log info "Generating talos config"
    talhelper genconfig
    just log info "Applying talos config"
    talhelper gencommand apply --extra-flags="--insecure" | bash
    just log info "Bootstrapping talos"
    until talhelper gencommand bootstrap | bash; do sleep 10; done
    just log info "Fetching kubeconfig"
    until talhelper gencommand kubeconfig --extra-flags="{{ justfile_dir() }} --force" | bash; do sleep 10; done

[private]
[script]
apps-crds:
    helmfile_file="{{ bootstrap_dir }}/helmfile.d/00-crds.yaml"
    test -f "$helmfile_file" || { just log error "Helmfile missing" file "$helmfile_file"; exit 1; }
    crds="$(helmfile --file "$helmfile_file" template --quiet \
        | yq eval-all --exit-status 'select(.kind == "CustomResourceDefinition")')" \
        || { just log error "Failed to render CRDs" file "$helmfile_file"; exit 1; }
    [ -z "$crds" ] && { just log error "No CRDs rendered" file "$helmfile_file"; exit 1; }
    if echo "$crds" | kubectl diff --filename - &>/dev/null; then
        just log info "CRDs already up-to-date"
        exit 0
    fi
    if echo "$crds" | kubectl apply --server-side --filename - &>/dev/null; then
        just log info "CRDs applied"
    else
        just log error "Failed to apply CRDs" file "$helmfile_file"
        exit 1
    fi

[private]
[script]
apps-helm:
    helmfile_file="{{ bootstrap_dir }}/helmfile.d/01-apps.yaml"
    test -f "$helmfile_file" || { just log error "Helmfile missing" file "$helmfile_file"; exit 1; }
    if helmfile --file "$helmfile_file" sync --hide-notes; then
        just log info "Helm releases synced"
    else
        just log error "Failed to sync Helm releases"
        exit 1
    fi

[private]
[script]
apps-namespaces:
    test -d "{{ kubernetes_dir }}/apps" || { just log error "kubernetes/apps directory missing"; exit 1; }
    for app in "{{ kubernetes_dir }}/apps"/*/; do
        ns="$(basename "$app")"
        if kubectl get namespace "$ns" &>/dev/null; then
            just log info "Namespace already exists" namespace "$ns"
        elif kubectl create namespace "$ns" --dry-run=client -o yaml \
                | kubectl apply --server-side --filename - &>/dev/null; then
            just log info "Namespace applied" namespace "$ns"
        else
            just log error "Failed to apply namespace" namespace "$ns"
            exit 1
        fi
    done

[private]
apps-preconditions:
    test -f "$KUBECONFIG"      || { just log error "kubeconfig not found at $KUBECONFIG"; exit 1; }
    test -f "$SOPS_AGE_KEY_FILE"
    test -f "{{ justfile_dir() }}/.sops.yaml"

[private]
[script]
apps-secrets:
    for secret in \
        "{{ bootstrap_dir }}/github-deploy-key.sops.yaml" \
        "{{ bootstrap_dir }}/sops-age.sops.yaml" \
        "{{ kubernetes_dir }}/components/sops/cluster-secrets.sops.yaml"
    do
        name="$(basename "$secret" .sops.yaml)"
        if [ ! -f "$secret" ]; then
            just log warn "Secret file missing, skipping" resource "$name"
            continue
        fi
        if sops exec-file "$secret" \
                "kubectl --namespace flux-system diff --filename {}" &>/dev/null; then
            just log info "Secret already up-to-date" resource "$name"
            continue
        fi
        if sops exec-file "$secret" \
                "kubectl --namespace flux-system apply --server-side --filename {}" &>/dev/null; then
            just log info "Secret applied" resource "$name"
        else
            just log error "Failed to apply secret" resource "$name"
            exit 1
        fi
    done

[private]
[script]
apps-wait-nodes:
    # Talos requires nodes to be Ready=False before applying resources; already-Ready
    # is also acceptable (re-run after the cluster is up).
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        just log info "Nodes are Ready, skipping wait"
        exit 0
    fi
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        just log info "Nodes not yet available, retrying in 10s..."
        sleep 10
    done
    just log info "Nodes available"
