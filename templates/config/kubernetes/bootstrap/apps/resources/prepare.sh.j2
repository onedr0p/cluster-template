#!/usr/bin/env bash

set -euo pipefail

# Set default values for the 'gum log' command
readonly LOG_ARGS=("log" "--time=rfc3339" "--formatter=text" "--structured" "--level")

# Verify required CLI tools are installed
function check_dependencies() {
    local deps=("gum" "jq" "kubectl" "kustomize" "sops" "yq")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        if ! command -v gum &>/dev/null; then
            printf "%s \033[1;95m%s\033[0m Missing required dependencies \033[0;30mdependencies=\033[0m\"%s\"\n" \
                "$(date --iso-8601=seconds)" "FATAL" "${missing[*]}"
            exit 1
        fi
        gum "${LOG_ARGS[@]}" fatal "Missing required dependencies" dependencies "${missing[*]}"
    fi

    gum "${LOG_ARGS[@]}" debug "Dependencies are installed" dependencies "${deps[*]}"
}

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    gum "${LOG_ARGS[@]}" debug "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        gum "${LOG_ARGS[@]}" info "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        gum "${LOG_ARGS[@]}" info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# Applications in the helmfile require Prometheus custom resources (e.g. servicemonitors)
function apply_prometheus_crds() {
    gum "${LOG_ARGS[@]}" debug "Applying Prometheus CRDs"

    # renovate: datasource=github-releases depName=prometheus-operator/prometheus-operator
    local -r version=v0.80.0
    local resources crds

    # Fetch resources using kustomize build
    if ! resources=$(kustomize build "https://github.com/prometheus-operator/prometheus-operator/?ref=${version}" 2>/dev/null) || [[ -z "${resources}" ]]; then
        gum "${LOG_ARGS[@]}" fatal "Failed to fetch Prometheus CRDs, check the version or the repository URL"
    fi

    # Extract only CustomResourceDefinitions
    if ! crds=$(echo "${resources}" | yq '. | select(.kind == "CustomResourceDefinition")' 2>/dev/null) || [[ -z "${crds}" ]]; then
        gum "${LOG_ARGS[@]}" fatal "No CustomResourceDefinitions found in the fetched resources"
    fi

    # Check if the CRDs are up-to-date
    if echo "${crds}" | kubectl diff --filename - &>/dev/null; then
        gum "${LOG_ARGS[@]}" info "Prometheus CRDs are up-to-date"
        return
    fi

    # Apply the CRDs
    if echo "${crds}" | kubectl apply --server-side --filename - &>/dev/null; then
        gum "${LOG_ARGS[@]}" info "Prometheus CRDs applied successfully"
    else
        gum "${LOG_ARGS[@]}" fatal "Failed to apply Prometheus CRDs"
    fi
}

# The application namespaces are created before applying the resources
function apply_namespaces() {
    gum "${LOG_ARGS[@]}" debug "Applying namespaces"

    local -r apps_dir="${KUBERNETES_DIR}/apps"

    if [[ ! -d "${apps_dir}" ]]; then
        gum "${LOG_ARGS[@]}" fatal "Directory does not exist" directory "${apps_dir}"
    fi

    for app in "${apps_dir}"/*/; do
        namespace=$(basename "${app}")

        # Check if the namespace resources are up-to-date
        if kubectl get namespace "${namespace}" &>/dev/null; then
            gum "${LOG_ARGS[@]}" info "Namespace resource is up-to-date" resource "${namespace}"
            continue
        fi

        # Apply the namespace resources
        if kubectl create namespace "${namespace}" --dry-run=client --output=yaml \
            | kubectl apply --server-side --filename - &>/dev/null;
        then
            gum "${LOG_ARGS[@]}" info "Namespace resource applied" resource "${namespace}"
        else
            gum "${LOG_ARGS[@]}" fatal "Failed to apply namespace resource" resource "${namespace}"
        fi
    done
}

# ConfigMaps to be applied before the helmfile charts are installed
function apply_configmaps() {
    gum "${LOG_ARGS[@]}" debug "Applying ConfigMaps"

    local -r configmaps=(
        "${KUBERNETES_DIR}/flux/components/common/cluster-settings.yaml"
    )

    for configmap in "${configmaps[@]}"; do
        if [ ! -f "${configmap}" ]; then
            gum "${LOG_ARGS[@]}" warn "File does not exist" file "${configmap}"
            continue
        fi
        if kubectl --namespace flux-system diff --filename "${configmap}" &>/dev/null; then
            gum "${LOG_ARGS[@]}" info "ConfigMap resource is up-to-date" resource "$(basename "${configmap}" ".yaml")"
            continue
        fi
        if kubectl --namespace flux-system apply --server-side --filename "${configmap}" &>/dev/null; then
            gum "${LOG_ARGS[@]}" info "ConfigMap resource applied successfully" resource "$(basename "${configmap}" ".yaml")"
        else
            gum "${LOG_ARGS[@]}" fatal "Failed to apply ConfigMap resource" resource "$(basename "${configmap}" ".yaml")"
        fi
    done
}

# SOPS secrets to be applied before the helmfile charts are installed
function apply_sops_secrets() {
    gum "${LOG_ARGS[@]}" debug "Applying secrets"

    local -r secrets=(
        "${KUBERNETES_DIR}/bootstrap/apps/resources/github-deploy-key.sops.yaml"
        "${KUBERNETES_DIR}/flux/components/common/cluster-secrets.sops.yaml"
        "${KUBERNETES_DIR}/flux/components/common/sops-age.sops.yaml"
    )

    for secret in "${secrets[@]}"; do
        if [ ! -f "${secret}" ]; then
            gum "${LOG_ARGS[@]}" warn "File does not exist" file "${secret}"
            continue
        fi

        # Check if the secret resources are up-to-date
        if sops exec-file "${secret}" "kubectl --namespace flux-system diff --filename {}" &>/dev/null; then
            gum "${LOG_ARGS[@]}" info "Secret resource is up-to-date" resource "$(basename "${secret}" ".yaml")"
            continue
        fi

        # Apply secret resources
        if sops exec-file "${secret}" "kubectl --namespace flux-system apply --server-side --filename {}" &>/dev/null; then
            gum "${LOG_ARGS[@]}" info "Secret resource applied successfully" resource "$(basename "${secret}" ".yaml")"
        else
            gum "${LOG_ARGS[@]}" fatal "Failed to apply secret resource" resource "$(basename "${secret}" ".yaml")"
        fi
    done
}

function success() {
    gum "${LOG_ARGS[@]}" info "Cluster is ready for installing helmfile apps"
}

function main() {
    check_dependencies
    wait_for_nodes
    apply_prometheus_crds
    apply_namespaces
    apply_configmaps
    apply_sops_secrets
    success
}

main "$@"
