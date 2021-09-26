#!/usr/bin/env bash

set -o errexit
set -o pipefail

export PROJECT_DIR
PROJECT_DIR=$(git rev-parse --show-toplevel)

# shellcheck disable=SC1091
source "${PROJECT_DIR}/.config.env"

show_help() {
cat << EOF
Usage: $(basename "$0") <options>
    -h, --help                      Display help
    --verify                        Verify .config.env settings
EOF
}

main() {
    local verify=

    parse_command_line "$@"

    verify_binaries

    if [[ "${verify}" == 1 ]]; then
        verify_metallb
        verify_kubevip
        verify_gpg_fp
        verify_git_repository
        verify_cloudflare
    else
        envsubst < "${PROJECT_DIR}/tmpl/.sops.yaml" > "${PROJECT_DIR}/.sops.yaml"
        # envsubst < "${PROJECT_DIR}/tmpl/cluster/cluster-secrets.sops.yaml" > "${PROJECT_DIR}/cluster/base/cluster-secrets.sops.yaml"
        # envsubst < "${PROJECT_DIR}/tmpl/cluster/cluster-settings.yaml" > "${PROJECT_DIR}/cluster/base/cluster-settings.yaml"
        # envsubst < "${PROJECT_DIR}/tmpl/cluster/gotk-sync.yaml" > "${PROJECT_DIR}/cluster/base/flux-system/gotk-sync.yaml"
        # envsubst < "${PROJECT_DIR}/tmpl/cluster/cert-manager-secret.sops.yaml" > "${PROJECT_DIR}/cluster/core/cert-manager/secret.sops.yaml"
        # sops --encrypt --in-place "${PROJECT_DIR}/cluster/base/cluster-secrets.sops.yaml"
        # sops --encrypt --in-place "${PROJECT_DIR}/cluster/core/cert-manager/secret.sops.yaml"
        # envsubst < "${PROJECT_DIR}/tmpl/ansible/hosts.yml" > "${PROJECT_DIR}/provision/ansible/inventory/hosts.yml"
        # envsubst < "${PROJECT_DIR}/tmpl/ansible/kube-vip.yml" > "${PROJECT_DIR}/provision/ansible/inventory/group_vars/kubernetes/kube-vip.yml"
        # envsubst < "${PROJECT_DIR}/tmpl/ansible/k8s-0.sops.yml" > "${PROJECT_DIR}/provision/ansible/inventory/host_vars/k8s-0.sops.yml"
        # envsubst < "${PROJECT_DIR}/tmpl/ansible/k8s-1.sops.yml" > "${PROJECT_DIR}/provision/ansible/inventory/host_vars/k8s-1.sops.yml"
        # sops --encrypt --in-place "${PROJECT_DIR}/provision/ansible/inventory/host_vars/k8s-0.sops.yml"
        # sops --encrypt --in-place "${PROJECT_DIR}/provision/ansible/inventory/host_vars/k8s-1.sops.yml"
    fi
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            --verify)
                verify=1
                ;;
            *)
                break
                ;;
        esac

        shift
    done

    if [[ -z "$verify" ]]; then
        verify=0
    fi
}

_has_binary() {
    command -v "${1}" >/dev/null 2>&1 || {
        printf >&2 "%s - Error - %s is not installed or not found in \$PATH\n" "$(date -u)" "${1}"
        exit 1
    }
}

_has_envar() {
    local option="${1}"
    [[ "${!option}" == "" ]] && {
        printf "%s - Error - Unset variable %s\n" "$(date -u)" "${option}"
        exit 1
    } || {
        printf "%s - Debug - Found variable '%s' with value '%s'\n" "$(date -u)" "${option}" "${!option}"
    }
}

_has_valid_ip() {
    local ip="${1}"
    local variable_name="${2}"
    
    if ! ipcalc "${ip}" | awk 'BEGIN{FS=":"; is_invalid=0} /^INVALID/ {is_invalid=1; print $1} END{exit is_invalid}' >/dev/null 2>&1; then
        printf "%s - Error - Variable '%s' has an invalid IP address '%s'\n" "$(date -u)" "${variable_name}" "${ip}"
        exit 1
    else
        printf "%s - Debug - Variable '%s' has a valid IP address '%s'\n" "$(date -u)" "${variable_name}" "${ip}"
    fi
}

verify_gpg_fp() {
    _has_envar "BOOTSTRAP_PERSONAL_KEY_FP"
    _has_envar "BOOTSTRAP_FLUX_KEY_FP"

    if ! gpg --list-keys "${BOOTSTRAP_PERSONAL_KEY_FP}" >/dev/null 2>&1; then
        printf "%s - Error - Invalid Personal GPG FP %s\n" "$(date -u)" "${BOOTSTRAP_PERSONAL_KEY_FP}"
        exit 1    
    else
        printf "%s - Debug - Found Personal GPG Fingerprint '%s'\n" "$(date -u)" "${BOOTSTRAP_PERSONAL_KEY_FP}"
    fi

    if ! gpg --list-keys "${BOOTSTRAP_FLUX_KEY_FP}" >/dev/null 2>&1; then
        printf "%s - Error - Invalid Flux GPG FP %s\n" "$(date -u)" "${BOOTSTRAP_FLUX_KEY_FP}"
        exit 1    
    else
        printf "%s - Debug - Found Flux GPG Fingerprint '%s'\n" "$(date -u)" "${BOOTSTRAP_FLUX_KEY_FP}"
    fi
}

verify_binaries() {
    _has_binary "ansible"
    _has_binary "envsubst"
    _has_binary "git"
    _has_binary "ipcalc"
    _has_binary "jq"
    _has_binary "kubectl"
    _has_binary "sops"
    _has_binary "task"
    _has_binary "terraform"
}

verify_kubevip() {
    _has_envar "BOOTSTRAP_ANSIBLE_KUBE_VIP_ADDRESS"
    _has_valid_ip "${BOOTSTRAP_ANSIBLE_KUBE_VIP_ADDRESS}" "BOOTSTRAP_ANSIBLE_KUBE_VIP_ADDRESS"
}

verify_metallb() {
    local ip_floor=
    local ip_ceil=
    _has_envar "BOOTSTRAP_METALLB_LB_RANGE"
    _has_envar "BOOTSTRAP_METALLB_TRAEFIK_ADDR"

    ip_floor=$(echo "${BOOTSTRAP_METALLB_LB_RANGE}" | cut -d- -f1)
    ip_ceil=$(echo "${BOOTSTRAP_METALLB_LB_RANGE}" | cut -d- -f2)

    _has_valid_ip "${ip_floor}" "BOOTSTRAP_METALLB_LB_RANGE"
    _has_valid_ip "${ip_ceil}" "BOOTSTRAP_METALLB_LB_RANGE"
    _has_valid_ip "${BOOTSTRAP_METALLB_TRAEFIK_ADDR}" "BOOTSTRAP_METALLB_TRAEFIK_ADDR"
}

verify_git_repository() {
    _has_envar "BOOTSTRAP_GIT_REPOSITORY"

    export GIT_TERMINAL_PROMPT=0
    pushd "$(mktemp -d)" >/dev/null 2>&1
    [ "$(git ls-remote "${BOOTSTRAP_GIT_REPOSITORY}" 2> /dev/null)" ] || {
        printf "%s - Error - Unable to find the remote Git repository '%s'\n" "$(date -u)" "${BOOTSTRAP_GIT_REPOSITORY}"
        exit 1
    }
    popd >/dev/null 2>&1
    export GIT_TERMINAL_PROMPT=1
}

verify_cloudflare() {
    local account_zone=
    local errors=

    _has_envar "BOOTSTRAP_CLOUDFLARE_ACCOUNT_ID"
    _has_envar "BOOTSTRAP_CLOUDFLARE_APIKEY"
    _has_envar "BOOTSTRAP_CLOUDFLARE_DOMAIN"
    _has_envar "BOOTSTRAP_CLOUDFLARE_EMAIL"

    # Try to retrieve zone information from Cloudflare's API
    account_zone=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${BOOTSTRAP_CLOUDFLARE_DOMAIN}&status=active&account.id=${BOOTSTRAP_CLOUDFLARE_ACCOUNT_ID}" \
        -H "X-Auth-Email: ${BOOTSTRAP_CLOUDFLARE_EMAIL}" \
        -H "X-Auth-Key: ${BOOTSTRAP_CLOUDFLARE_APIKEY}" \
        -H "Content-Type: application/json"
    )

    if [[ "$(echo "${account_zone}" | jq ".success")" == "true" ]]; then
        printf "%s - Debug - Verified Cloudflare Account and Zone information\n" "$(date -u)"
        exit 0
    else
        errors=$(echo "${account_zone}" | jq -c ".errors")
        printf "%s - Error - Unable to get Cloudflare Account and Zone information %s\n" "$(date -u)" "${errors}"
        exit 1
    fi
}

main "$@"
