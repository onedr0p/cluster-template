#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR="${1:?Kubernetes location not specified}"

# Flux substitutes ${SECRET_DOMAIN} from cluster-secrets at apply time. Use a
# placeholder so hostname fields in Gateways, HTTPRoutes and DNSEndpoints
# validate against their schemas instead of being skipped; --strict fails on
# any other unset variable.
SECRET_DOMAIN="example.com"

kubeconform_args=(
    "-strict"
    "-ignore-missing-schemas"
    "-skip"
    "Secret"
    "-schema-location"
    "default"
    "-schema-location"
    "https://k8s-schemas.home-operations.com/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "-verbose"
)

find "${KUBERNETES_DIR}/apps" -type f -name kustomization.yaml -print0 \
    | while IFS= read -r -d '' file; do
        dir="$(dirname "${file}")"
        echo "=== Validating kustomization in ${dir} ==="
        kustomize build "${dir}" --load-restrictor=LoadRestrictionsNone \
            | SECRET_DOMAIN="${SECRET_DOMAIN}" flux envsubst --strict \
            | kubeconform "${kubeconform_args[@]}"
    done
