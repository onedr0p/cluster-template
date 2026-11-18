#!/usr/bin/env bash

set -euo pipefail

KUBERNETES_DIR="${1:?Kubernetes location not specified}"

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

# The root flux-system Kustomization applies the namespace kustomizations
# without postBuild substitution, so build them as-is.
namespaces=""
for dir in "${KUBERNETES_DIR}"/apps/*/; do
    namespaces+="$(kustomize build "${dir}" --load-restrictor=LoadRestrictionsNone)"$'\n---\n'
done

# flate renders every Flux Kustomization and HelmRelease with Flux's postBuild
# behaviour. SOPS leaves key names in plaintext, so supply each encrypted
# Secret with placeholder values for the substitution.
supply="$(yq 'select(.kind == "Secret" and has("sops")) | .stringData[] = "example.com" | del(.sops)' <<<"${namespaces}")"
apps="$(flate build all --no-progress --strict-substitutions --supply <(printf '%s\n' "${supply}"))"

kubeconform "${kubeconform_args[@]}" <<<"${namespaces}${apps}"
