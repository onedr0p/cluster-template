#!/usr/bin/env bash
# Full-fidelity bootstrap e2e: takes maintenance-mode Talos VMs, discovers
# their hardware the same way the README instructs users to, writes a
# cluster.toml from the discovered facts, and runs the template's real
# bootstrap flow against them.
#
# Two provisioning paths share this test body:
#   - CI: talosctl-cluster-action boots the nodes (talos-cluster.yaml) and
#     passes E2E_CONTROLPLANE_IPS / E2E_WORKER_IPS / E2E_CIDR; the action's
#     post step destroys them.
#   - Local: run with no env set; the script boots and destroys the cluster
#     itself. Requires /dev/kvm, passwordless sudo, qemu-system-x86, and the
#     repo's mise toolchain and Docker on PATH.
#
# Renders into the working tree like any configure run.
set -euo pipefail

NAME="${E2E_NAME:-template-e2e}"
CIDR="${E2E_CIDR:-10.9.0.0/24}"
PREFIX="${CIDR%/*}"
PREFIX="${PREFIX%.*}"
TALOSCTL="$(command -v talosctl)"
# The Image Factory vanilla schematic, matching the ISO the nodes boot from.
SCHEMATIC="376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"

if [ -n "${E2E_CONTROLPLANE_IPS:-}" ]; then
    PROVISIONED=true
    IFS=',' read -r -a CONTROLPLANES <<< "$E2E_CONTROLPLANE_IPS"
    IFS=',' read -r -a WORKERS <<< "${E2E_WORKER_IPS:-}"
else
    PROVISIONED=false
    CONTROLPLANES=("$PREFIX.2")
    WORKERS=("$PREFIX.3")
fi
NODES=("${CONTROLPLANES[@]}" "${WORKERS[@]}")
# The VMs reach the host at the gateway address; the rendered workspace is
# served from there over git smart HTTP so Flux can sync it.
GIT_HOST="${E2E_GATEWAY:-$PREFIX.1}"
GIT_PORT=8418
GIT_SSH_PORT=8419
GIT_SERVER_NAME="$NAME-soft-serve"
GIT_SERVER_MANAGED=false

# The provisioner runs under sudo and writes state relative to its cwd and
# TALOSCONFIG, so both are pointed at a scratch dir to keep root-owned files
# out of the repo.
STATE="$(mktemp -d)"

cleanup() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "==> e2e failed (rc=$rc), collecting diagnostics"
        kubectl get pods --all-namespaces 2>/dev/null || true
        kubectl get gitrepositories,kustomizations,helmreleases --all-namespaces 2>/dev/null || true
        kubectl get events --all-namespaces --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
        docker logs "$GIT_SERVER_NAME" 2>/dev/null | tail -20 || true
        for ip in "${NODES[@]}"; do
            talosctl -n "$ip" dmesg 2>/dev/null | tail -20 || true
        done
    fi
    if [ "$GIT_SERVER_MANAGED" = true ]; then
        docker rm --force "$GIT_SERVER_NAME" >/dev/null 2>&1 || true
    fi
    if [ "$PROVISIONED" = false ]; then
        (cd "$STATE" && sudo -E env TALOSCONFIG="$STATE/talosconfig" \
            "$TALOSCTL" cluster destroy --name "$NAME" --provisioner qemu >/dev/null 2>&1) || true
    fi
    sudo rm -rf "$STATE" || true
    exit "$rc"
}
trap cleanup EXIT

if [ "$PROVISIONED" = false ]; then
    echo "==> booting maintenance-mode nodes"
    (cd "$STATE" && sudo -E env TALOSCONFIG="$STATE/talosconfig" \
        "$TALOSCTL" cluster create qemu --name "$NAME" --presets iso,maintenance \
        --controlplanes 1 --workers 1 --cidr "$CIDR" \
        --memory-controlplanes 4GiB --memory-workers 3GiB)
fi

echo "==> waiting for the maintenance API"
for ip in "${NODES[@]}"; do
    until talosctl -n "$ip" get links --insecure >/dev/null 2>&1; do sleep 5; done
done

echo "==> discovering node hardware"
declare -A MACS DISKS
for ip in "${NODES[@]}"; do
    MACS[$ip]="$(talosctl -n "$ip" get links --insecure -o json \
        | jq -r 'select(.spec.type == "ether" and .spec.operationalState == "up" and (.metadata.id | startswith("bond") | not)) | .spec.hardwareAddr' | head -1)"
    DISKS[$ip]="/dev/$(talosctl -n "$ip" get disks --insecure -o json \
        | jq -r 'select(.spec.readonly == false and (.metadata.id | startswith("loop") | not)) | .metadata.id' | head -1)"
    echo "    $ip mac=${MACS[$ip]} disk=${DISKS[$ip]}"
done

echo "==> generating cluster.toml"
cat > cluster.toml <<EOF
[network]
node_cidr       = "$CIDR"
default_gateway = "${E2E_GATEWAY:-$PREFIX.1}"

[kubernetes.api]
addr = "$PREFIX.100"

[gateways]
internal = "$PREFIX.101"
dns      = "$PREFIX.102"

[domain]
name = "e2e.example.com"

[dns]
provider = "none"

[repository]
url = "http://$GIT_HOST:$GIT_PORT/repo.git"

[talos]
schematic_id = "$SCHEMATIC"
EOF
index=0
for ip in "${NODES[@]}"; do
    controller=false
    for cp in "${CONTROLPLANES[@]}"; do [ "$ip" = "$cp" ] && controller=true; done
    cat >> cluster.toml <<EOF

[[nodes]]
name       = "e2e-$index"
address    = "$ip"
controller = $controller
disk       = "${DISKS[$ip]}"
mac_addr   = "${MACS[$ip]}"
EOF
    index=$((index + 1))
done

echo "==> configure"
just init
just configure

# Flux's FluxInstance only reports Ready once its Git sync succeeds, so the
# rendered kubernetes/ tree is committed to a bare repo and served to the
# cluster — the same push-then-bootstrap flow the README walks users through.
echo "==> publishing rendered repo"
mkdir -p "$STATE/gitwork"
cp -r kubernetes "$STATE/gitwork/"
git -C "$STATE/gitwork" init --quiet --initial-branch main
git -C "$STATE/gitwork" add --all
git -C "$STATE/gitwork" -c user.name=e2e -c user.email=e2e@cluster.local \
    commit --quiet --message "rendered workspace"

if [ -n "${E2E_SOFT_SERVE_PRIVATE_KEY:-}" ]; then
    cp "$E2E_SOFT_SERVE_PRIVATE_KEY" "$STATE/soft-serve-key"
else
    ssh-keygen -q -t ed25519 -N "" -f "$STATE/soft-serve-key"
    docker run --detach --name "$GIT_SERVER_NAME" \
        --volume "$STATE/soft-serve:/soft-serve" \
        --publish "$GIT_PORT:23232" \
        --publish "$GIT_SSH_PORT:23231" \
        --env "SOFT_SERVE_INITIAL_ADMIN_KEYS=$(cat "$STATE/soft-serve-key.pub")" \
        ghcr.io/charmbracelet/soft-serve:v0.11.6 >/dev/null
    GIT_SERVER_MANAGED=true
fi
chmod 600 "$STATE/soft-serve-key"

SSH_COMMAND="ssh -i $STATE/soft-serve-key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
until $SSH_COMMAND -p "$GIT_SSH_PORT" localhost info >/dev/null 2>&1; do sleep 1; done
GIT_SSH_COMMAND="$SSH_COMMAND" git -C "$STATE/gitwork" push --quiet \
    "ssh://localhost:$GIT_SSH_PORT/repo.git" main
until git ls-remote "http://$GIT_HOST:$GIT_PORT/repo.git" >/dev/null 2>&1; do sleep 1; done

echo "==> bootstrap talos"
just bootstrap talos

echo "==> bootstrap apps"
just bootstrap apps

echo "==> asserting cluster health"
kubectl wait nodes --all --for=condition=Ready --timeout=10m
for ns in kube-system cert-manager flux-system; do
    kubectl wait pods --namespace "$ns" --all --for=condition=Ready --timeout=10m
done

echo "==> asserting flux reconciliation"
kubectl wait fluxinstance/flux --namespace flux-system --for=condition=Ready --timeout=10m
kubectl wait gitrepositories --all --all-namespaces --for=condition=Ready --timeout=5m
kubectl wait kustomizations --all --all-namespaces --for=condition=Ready --timeout=10m
kubectl wait helmreleases --all --all-namespaces --for=condition=Ready --timeout=10m
kubectl get nodes --output wide
kubectl get kustomizations,helmreleases --all-namespaces
echo "==> e2e bootstrap succeeded"
