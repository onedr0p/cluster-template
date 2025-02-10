#!/usr/bin/env bash

set -euo pipefail

# Log messages with timestamps and function names
function log() {
    echo -e "\033[0;32m[$(date --iso-8601=seconds)] (${FUNCNAME[1]}) $*\033[0m"
}

# Apply Prometheus CRDs
function apply_prometheus_crds() {
    # renovate: datasource=github-releases depName=prometheus-operator/prometheus-operator
    local -r version=v0.80.0

    local -r crds=(
        "alertmanagerconfigs"
        "alertmanagers"
        "podmonitors"
        "probes"
        "prometheusagents"
        "prometheuses"
        "prometheusrules"
        "scrapeconfigs"
        "servicemonitors"
        "thanosrulers"
    )

    for crd in "${crds[@]}"; do
        if kubectl get crd "${crd}.monitoring.coreos.com" &>/dev/null; then
            log "Prometheus CRD '${crd}' is up-to-date. Skipping..."
            continue
        fi
        log "Applying Prometheus CRD '${crd}'..."
        kubectl apply --server-side \
            --filename "https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${version}/example/prometheus-operator-crd/monitoring.coreos.com_${crd}.yaml"
    done
}

function main() {
    apply_prometheus_crds
}

main "$@"
