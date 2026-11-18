#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR="${1:?Kubernetes location not specified}"

SECRET_DOMAIN="${SECRET_DOMAIN:-example.com}"

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

# envsubst substitutes every exported variable, so it runs with an empty
# environment; env -i also clears PATH, hence the absolute path.
flux="$(command -v flux)"

find "${KUBERNETES_DIR}/apps" -type f -name kustomization.yaml -print0 \
    | while IFS= read -r -d '' file; do
        dir="$(dirname "${file}")"
        echo "=== Validating kustomization in ${dir} ==="
        kustomize build "${dir}" --load-restrictor=LoadRestrictionsNone \
            | env -i SECRET_DOMAIN="${SECRET_DOMAIN}" "${flux}" envsubst --strict \
            | kubeconform "${kubeconform_args[@]}"
    done
