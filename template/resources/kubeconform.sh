#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR="${1:?Kubernetes location not specified}"

kubeconform_args=(
    "-strict"
    "-ignore-missing-schemas"
    "-skip"
    "Gateway,HTTPRoute,Secret,DNSEndpoint"
    "-schema-location"
    "default"
    "-schema-location"
    "https://k8s-schemas.home-operations.com/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
    "-verbose"
)

echo "=== Validating standalone manifests in ${KUBERNETES_DIR}/flux ==="
find "${KUBERNETES_DIR}/flux" -type f -name '*.yaml' ! -name kustomization.yaml -print0 \
    | xargs -0 -r kubeconform "${kubeconform_args[@]}"

find "${KUBERNETES_DIR}/flux" "${KUBERNETES_DIR}/apps" -type f -name kustomization.yaml -print0 \
    | while IFS= read -r -d '' file; do
        dir="$(dirname "${file}")"
        echo "=== Validating kustomization in ${dir} ==="
        kustomize build "${dir}" --load-restrictor=LoadRestrictionsNone | kubeconform "${kubeconform_args[@]}"
    done
