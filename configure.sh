#!/usr/bin/env bash

set -o errexit
set -o pipefail

# shellcheck disable=SC2155
export PROJECT_DIR=$(git rev-parse --show-toplevel)

# shellcheck disable=SC2155
export GPG_TTY=$(tty)

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
        verify_ansible_hosts
        verify_metallb
        verify_kubevip
        verify_gpg
        verify_git_repository
        verify_cloudflare
        success
    else
        # sops configuration file
        envsubst < "${PROJECT_DIR}/tmpl/.sops.yaml" \
            > "${PROJECT_DIR}/.sops.yaml"
        # cluster
        envsubst < "${PROJECT_DIR}/tmpl/cluster/cluster-settings.yaml" \
            > "${PROJECT_DIR}/cluster/base/cluster-settings.yaml"
        envsubst < "${PROJECT_DIR}/tmpl/cluster/gotk-sync.yaml" \
            > "${PROJECT_DIR}/cluster/base/flux-system/gotk-sync.yaml"
        envsubst < "${PROJECT_DIR}/tmpl/cluster/kube-vip-daemonset.yaml" \
            > "${PROJECT_DIR}/cluster/core/kube-system/kube-vip/daemon-set.yaml"
        envsubst < "${PROJECT_DIR}/tmpl/cluster/cluster-secrets.sops.yaml" \
            > "${PROJECT_DIR}/cluster/base/cluster-secrets.sops.yaml"
        envsubst < "${PROJECT_DIR}/tmpl/cluster/cert-manager-secret.sops.yaml" \
            > "${PROJECT_DIR}/cluster/core/cert-manager/secret.sops.yaml"
        sops --encrypt --in-place "${PROJECT_DIR}/cluster/base/cluster-secrets.sops.yaml"
        sops --encrypt --in-place "${PROJECT_DIR}/cluster/core/cert-manager/secret.sops.yaml"
        # terraform
        envsubst < "${PROJECT_DIR}/tmpl/terraform/secret.sops.yaml" \
            > "${PROJECT_DIR}/provision/terraform/cloudflare/secret.sops.yaml"
        sops --encrypt --in-place "${PROJECT_DIR}/provision/terraform/cloudflare/secret.sops.yaml"
        # ansible
        envsubst < "${PROJECT_DIR}/tmpl/ansible/kube-vip.yml" \
            > "${PROJECT_DIR}/provision/ansible/inventory/group_vars/kubernetes/kube-vip.yml"
        generate_ansible_hosts
        generate_ansible_host_secrets
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
        _log "ERROR" "${1} is not installed or not found in \$PATH"
        exit 1
    }
}

_has_envar() {
    local option="${1}"
    # shellcheck disable=SC2015
    [[ "${!option}" == "" ]] && {
        _log "ERROR" "Unset variable ${option}"
        exit 1
    } || {
        _log "INFO" "Found variable '${option}' with value '${!option}'"
    }
}

_has_valid_ip() {
    local ip="${1}"
    local variable_name="${2}"
    
    if ! ipcalc "${ip}" | awk 'BEGIN{FS=":"; is_invalid=0} /^INVALID/ {is_invalid=1; print $1} END{exit is_invalid}' >/dev/null 2>&1; then
        _log "INFO" "Variable '${variable_name}' has an invalid IP address '${ip}'"
        exit 1
    else
        _log "INFO" "Variable '${variable_name}' has a valid IP address '${ip}'"
    fi
}

verify_gpg() {
    _has_envar "BOOTSTRAP_PERSONAL_KEY_FP"
    _has_envar "BOOTSTRAP_FLUX_KEY_FP"

    if ! gpg --list-keys "${BOOTSTRAP_PERSONAL_KEY_FP}" >/dev/null 2>&1; then
         _log "ERROR" "Invalid Personal GPG FP ${BOOTSTRAP_PERSONAL_KEY_FP}"
        exit 1    
    else
        _log "INFO" "Found Personal GPG Fingerprint '${BOOTSTRAP_PERSONAL_KEY_FP}'"
    fi

    if ! gpg --list-keys "${BOOTSTRAP_FLUX_KEY_FP}" >/dev/null 2>&1; then
         _log "ERROR" "Invalid Flux GPG FP '${BOOTSTRAP_FLUX_KEY_FP}'"
        exit 1    
    else
         _log "INFO" "Found Flux GPG Fingerprint '${BOOTSTRAP_FLUX_KEY_FP}'"
    fi
}

verify_binaries() {
    _has_binary "ansible"
    _has_binary "envsubst"
    _has_binary "flux"
    _has_binary "git"
    _has_binary "gpg"
    _has_binary "helm"
    _has_binary "ipcalc"
    _has_binary "jq"
    _has_binary "sops"
    _has_binary "ssh"
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
        _log "ERROR" "Unable to find the remote Git repository '${BOOTSTRAP_GIT_REPOSITORY}'"
        exit 1
    }
    popd >/dev/null 2>&1
    export GIT_TERMINAL_PROMPT=1
}

verify_cloudflare() {
    local account_zone=
    local errors=

    _has_envar "BOOTSTRAP_CLOUDFLARE_APIKEY"
    _has_envar "BOOTSTRAP_CLOUDFLARE_DOMAIN"
    _has_envar "BOOTSTRAP_CLOUDFLARE_EMAIL"

    # Try to retrieve zone information from Cloudflare's API
    account_zone=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${BOOTSTRAP_CLOUDFLARE_DOMAIN}&status=active" \
        -H "X-Auth-Email: ${BOOTSTRAP_CLOUDFLARE_EMAIL}" \
        -H "X-Auth-Key: ${BOOTSTRAP_CLOUDFLARE_APIKEY}" \
        -H "Content-Type: application/json"
    )

    if [[ "$(echo "${account_zone}" | jq ".success")" == "true" ]]; then
        _log "INFO" "Verified Cloudflare Account and Zone information"
    else
        errors=$(echo "${account_zone}" | jq -c ".errors")
        _log "ERROR" "Unable to get Cloudflare Account and Zone information ${errors}"
        exit 1
    fi
}

verify_ansible_hosts() {
    local node_id=
    local node_addr=
    local node_username=
    local node_password=
    local node_control=

    for var in "${!BOOTSTRAP_ANSIBLE_HOST_ADDR_@}"; do
        node_id=$(echo "${var}" | awk -F"_" '{print $5}')
        node_addr="BOOTSTRAP_ANSIBLE_HOST_ADDR_${node_id}"
        node_username="BOOTSTRAP_ANSIBLE_SSH_USERNAME_${node_id}"
        node_password="BOOTSTRAP_ANSIBLE_SUDO_PASSWORD_${node_id}"
        node_control="BOOTSTRAP_ANSIBLE_CONTROL_NODE_${node_id}"

        _has_envar "${node_addr}"
        _has_envar "${node_username}"
        _has_envar "${node_password}"
        _has_envar "${node_control}"

        if ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${!node_username}"@"${!var}" "true"; then
            _log "INFO" "Successfully SSH'ed into host '${!var}' with username '${!node_username}'"
        else
            _log "ERROR" "Unable to SSH into host '${!var}' with username '${!node_username}'"
            exit 1
        fi
    done
}

success() {
    printf "\nAll checks pass!"
    exit 0
}

generate_ansible_host_secrets() {
    local node_id=
    local node_username=
    local node_password=
    for var in "${!BOOTSTRAP_ANSIBLE_HOST_ADDR_@}"; do
        node_id=$(echo "${var}" | awk -F"_" '{print $5}')
        {
            node_username="BOOTSTRAP_ANSIBLE_SSH_USERNAME_${node_id}"
            node_password="BOOTSTRAP_ANSIBLE_SUDO_PASSWORD_${node_id}"
            printf "kind: Secret\n"
            printf "ansible_user: %s\n" "${!node_username}"
            printf "ansible_become_pass: %s\n" "${!node_password}"
        } > "${PROJECT_DIR}/provision/ansible/inventory/host_vars/k8s-${node_id}.sops.yml"
        sops --encrypt --in-place "${PROJECT_DIR}/provision/ansible/inventory/host_vars/k8s-${node_id}.sops.yml"
    done
}

generate_ansible_hosts() {
    local worker_node_count=
    {
        printf "kubernetes:\n"
        printf "  children:\n"
        printf "    master:\n"
        printf "      hosts:\n"
        worker_node_count=0
        for var in "${!BOOTSTRAP_ANSIBLE_HOST_ADDR_@}"; do
            node_id=$(echo "${var}" | awk -F"_" '{print $5}')
            node_control="BOOTSTRAP_ANSIBLE_CONTROL_NODE_${node_id}"
            if [[ "${!node_control}" == "true" ]]; then
                printf "        k8s-%s:\n" "${node_id}"
                printf "          ansible_host: %s\n" "${!var}"
            else
                worker_node_count=$((worker_node_count+1))
            fi
        done
        if [[ ${worker_node_count} -gt 0 ]]; then
            printf "    worker:\n"
            printf "      hosts:\n"
            for var in "${!BOOTSTRAP_ANSIBLE_HOST_ADDR_@}"; do
                node_id=$(echo "${var}" | awk -F"_" '{print $5}')
                node_control="BOOTSTRAP_ANSIBLE_CONTROL_NODE_${node_id}"
                if [[ "${!node_control}" == "false" ]]; then
                    printf "        k8s-%s:\n" "${node_id}"
                    printf "          ansible_host: %s\n" "${!var}"
                fi
            done
        fi
    } > "${PROJECT_DIR}/provision/ansible/inventory/hosts.yml"
}

_log() {
    local type="${1}"
    local msg="${2}"
    printf "[%s] [%s] %s\n" "$(date -u)" "${type}" "${msg}"
}

main "$@"
