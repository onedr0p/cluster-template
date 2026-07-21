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
#     itself. Requires Docker, /dev/kvm, passwordless sudo, qemu-system-x86,
#     and the repo's mise toolchain on PATH.
#
# Renders into the working tree like any configure run.
set -euo pipefail

NAME="${E2E_NAME:-template-e2e}"
MODE="${1:-all}"
E2E_DIR=".github/template-tests/e2e"
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
GIT_SERVER_CONTAINER=""

# The provisioner runs under sudo and writes state relative to its cwd and
# TALOSCONFIG, so both are pointed at a scratch dir to keep root-owned files
# out of the repo.
if [ -n "${E2E_STATE:-}" ]; then
    STATE="$E2E_STATE"
    STATE_OWNED=false
else
    STATE="$(mktemp -d)"
    STATE_OWNED=true
fi
mkdir -p "$STATE"
GIT_PUSH_URL="http://127.0.0.1:$GIT_PORT/repo.git"

cleanup() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "==> e2e failed (rc=$rc), collecting diagnostics"
        kubectl get pods --all-namespaces 2>/dev/null || true
        kubectl get gitrepositories,kustomizations,helmreleases --all-namespaces 2>/dev/null || true
        kubectl get events --all-namespaces --sort-by=.lastTimestamp 2>/dev/null | tail -30 || true
        [ -n "$GIT_SERVER_CONTAINER" ] && docker logs --tail 5 "$GIT_SERVER_CONTAINER" 2>/dev/null || true
        for ip in "${NODES[@]}"; do
            talosctl -n "$ip" dmesg 2>/dev/null | tail -20 || true
        done
    fi
    if [ "$MODE" = all ]; then
        [ -n "$GIT_SERVER_CONTAINER" ] && docker stop "$GIT_SERVER_CONTAINER" >/dev/null 2>&1 || true
    fi
    if [ "$MODE" = all ] && [ "$PROVISIONED" = false ]; then
        (cd "$STATE" && sudo -E env TALOSCONFIG="$STATE/talosconfig" \
            "$TALOSCTL" cluster destroy --name "$NAME" --provisioner qemu >/dev/null 2>&1) || true
    fi
    if [ "$MODE" = all ] && [ "$STATE_OWNED" = true ]; then
        sudo rm -rf "$STATE" || true
    fi
    exit "$rc"
}
trap cleanup EXIT

start_local_git_server() {
    GIT_SERVER_CONTAINER="$NAME-git"
    docker run --detach --rm --name "$GIT_SERVER_CONTAINER" \
        --publish "$GIT_PORT:23232" \
        --env SOFT_SERVE_GIT_ENABLED=false \
        --env SOFT_SERVE_LFS_ENABLED=false \
        --env SOFT_SERVE_SSH_LISTEN_ADDR=127.0.0.1:23231 \
        --env SOFT_SERVE_STATS_ENABLED=false \
        --entrypoint /bin/sh \
        ghcr.io/charmbracelet/soft-serve:v0.11.6 \
        -c 'set -eu; ssh-keygen -q -t ed25519 -N "" -f /tmp/admin; export SOFT_SERVE_INITIAL_ADMIN_KEYS="$(cat /tmp/admin.pub)"; /usr/local/bin/soft serve & pid=$!; until ssh -q -i /tmp/admin -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -p 23231 localhost settings anon-access read-write; do sleep 1; done; ssh -q -i /tmp/admin -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -p 23231 localhost repo create repo; wait "$pid"' \
        >/dev/null
    deadline=$((SECONDS + 60))
    until git ls-remote "$GIT_PUSH_URL" >/dev/null 2>&1; do
        if (( SECONDS >= deadline )); then
            just log fatal "Soft Serve is not reachable"
        fi
        sleep 1
    done
}

prepare() {
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
export E2E_CIDR="$CIDR"
export E2E_GATEWAY="${E2E_GATEWAY:-$PREFIX.1}"
export E2E_GIT_HOST="$GIT_HOST"
export E2E_GIT_PORT="$GIT_PORT"
export E2E_PREFIX="$PREFIX"
export E2E_SCHEMATIC="$SCHEMATIC"
envsubst '${E2E_CIDR} ${E2E_GATEWAY} ${E2E_GIT_HOST} ${E2E_GIT_PORT} ${E2E_PREFIX} ${E2E_SCHEMATIC}' \
    < "$E2E_DIR/cluster.toml.tmpl" > cluster.toml
index=0
for ip in "${NODES[@]}"; do
    controller=false
    for cp in "${CONTROLPLANES[@]}"; do [ "$ip" = "$cp" ] && controller=true; done
    export E2E_NODE_NAME="e2e-$index"
    export E2E_NODE_ADDRESS="$ip"
    export E2E_NODE_CONTROLLER="$controller"
    export E2E_NODE_DISK="${DISKS[$ip]}"
    export E2E_NODE_MAC="${MACS[$ip]}"
    envsubst '${E2E_NODE_ADDRESS} ${E2E_NODE_CONTROLLER} ${E2E_NODE_DISK} ${E2E_NODE_MAC} ${E2E_NODE_NAME}' \
        < "$E2E_DIR/node.toml.tmpl" >> cluster.toml
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
git -C "$STATE/gitwork" push --quiet "$GIT_PUSH_URL" main
}

assert_cluster_health() {
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
}

foundation() {
deadline=$((SECONDS + 60))
until git ls-remote "http://$GIT_HOST:$GIT_PORT/repo.git" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
        just log fatal "Rendered repository server is not reachable"
    fi
    sleep 1
done
echo "==> bootstrap talos"
just bootstrap talos

echo "==> bootstrap apps"
just bootstrap apps
assert_cluster_health

echo "==> asserting bootstrap idempotency"
just configure
just bootstrap talos
just bootstrap apps
assert_cluster_health
}

flux_sops() {
echo "==> asserting Flux SOPS decryption"
SOPS_SECRET="$STATE/gitwork/kubernetes/apps/default/e2e-sops.sops.yaml"
export E2E_SOPS_VALUE=flux-decrypted
envsubst '${E2E_SOPS_VALUE}' < "$E2E_DIR/sops-secret.yaml.tmpl" > "$SOPS_SECRET"
sops encrypt --filename-override kubernetes/apps/default/e2e-sops.sops.yaml \
    --in-place "$SOPS_SECRET"
yq --inplace '.resources += ["./e2e-sops.sops.yaml"]' \
    "$STATE/gitwork/kubernetes/apps/default/kustomization.yaml"
git -C "$STATE/gitwork" add --all
git -C "$STATE/gitwork" -c user.name=e2e -c user.email=e2e@cluster.local \
    commit --quiet --message "test Flux SOPS decryption"
git -C "$STATE/gitwork" push --quiet "$GIT_PUSH_URL" main
flux reconcile kustomization cluster-apps --with-source --timeout=10m
test "$(kubectl get secret e2e-sops --namespace default \
    --output jsonpath='{.data.value}' | base64 --decode)" = "flux-decrypted"
}

networking() {
echo "==> asserting pod networking and DNS"
export E2E_CONTROLPLANE_NODE="$(kubectl get nodes \
    --selector=node-role.kubernetes.io/control-plane \
    --output jsonpath='{.items[0].metadata.name}')"
export E2E_WORKER_NODE="$(kubectl get nodes \
    --selector='!node-role.kubernetes.io/control-plane' \
    --output jsonpath='{.items[0].metadata.name}')"
NETWORK_CONFIG="$STATE/network.yaml"
envsubst '${E2E_CONTROLPLANE_NODE} ${E2E_WORKER_NODE}' \
    < "$E2E_DIR/network.yaml.tmpl" > "$NETWORK_CONFIG"
kubectl apply --filename "$NETWORK_CONFIG"
kubectl wait pods/e2e-network-server pods/e2e-network-client \
    --namespace default --for=condition=Ready --timeout=5m
SERVER_IP="$(kubectl get pod e2e-network-server --namespace default \
    --output jsonpath='{.status.podIP}')"
kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=10s "$SERVER_IP:8080"
kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=10s e2e-network-server.default.svc.cluster.local:8080
kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=10s github.com:443
kubectl apply --filename "$E2E_DIR/cilium-network-policy.yaml"
deadline=$((SECONDS + 60))
while kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=2s "$SERVER_IP:8080" &>/dev/null; do
    if (( SECONDS >= deadline )); then
        just log fatal "CiliumNetworkPolicy did not block pod traffic"
    fi
    sleep 2
done
kubectl delete ciliumnetworkpolicy e2e-deny-server --namespace default
deadline=$((SECONDS + 60))
until kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=2s "$SERVER_IP:8080" &>/dev/null; do
    if (( SECONDS >= deadline )); then
        just log fatal "Pod traffic did not recover after removing CiliumNetworkPolicy"
    fi
    sleep 2
done
}

summary() {
kubectl get nodes --output wide
kubectl get kustomizations,helmreleases --all-namespaces
echo "==> e2e bootstrap succeeded"
}

case "$MODE" in
    prepare)    prepare ;;
    foundation) foundation ;;
    flux-sops)  flux_sops ;;
    networking) networking ;;
    summary)    summary ;;
    all)
        start_local_git_server
        prepare
        foundation
        flux_sops
        networking
        summary
        ;;
    *)
        echo "usage: $0 {prepare|foundation|flux-sops|networking|summary|all}" >&2
        exit 2
        ;;
esac
