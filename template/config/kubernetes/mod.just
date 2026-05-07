set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[private]
default:
    just kube -l

[doc('Force Flux to pull in changes from your Git repository')]
[group('kubernetes')]
reconcile:
    test -f "$KUBECONFIG" || { just log error "kubeconfig not found at $KUBECONFIG"; exit 1; }
    flux --namespace flux-system reconcile kustomization flux-system --with-source
