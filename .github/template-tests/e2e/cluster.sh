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
#     repo's mise toolchain on PATH.
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
GIT_SERVER_PID=""

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
        tail -5 "$STATE/git-server.log" 2>/dev/null || true
        for ip in "${NODES[@]}"; do
            talosctl -n "$ip" dmesg 2>/dev/null | tail -20 || true
        done
    fi
    [ -n "$GIT_SERVER_PID" ] && kill "$GIT_SERVER_PID" 2>/dev/null || true
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
git clone --quiet --bare "$STATE/gitwork" "$STATE/repo.git"
python3 .github/template-tests/e2e/git-server.py "$STATE/repo.git" "$GIT_PORT" \
    >"$STATE/git-server.log" 2>&1 &
GIT_SERVER_PID=$!

echo "==> bootstrap talos"
just bootstrap talos

echo "==> bootstrap apps"
just bootstrap apps

echo "==> asserting bootstrap idempotency"
just configure
just bootstrap talos
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

echo "==> asserting Flux SOPS decryption"
SOPS_SECRET="$STATE/gitwork/kubernetes/apps/default/e2e-sops.sops.yaml"
cat > "$SOPS_SECRET" <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: e2e-sops
  namespace: default
stringData:
  value: flux-decrypted
EOF
sops encrypt --filename-override kubernetes/apps/default/e2e-sops.sops.yaml \
    --in-place "$SOPS_SECRET"
yq --inplace '.resources += ["./e2e-sops.sops.yaml"]' \
    "$STATE/gitwork/kubernetes/apps/default/kustomization.yaml"
git -C "$STATE/gitwork" add --all
git -C "$STATE/gitwork" -c user.name=e2e -c user.email=e2e@cluster.local \
    commit --quiet --message "test Flux SOPS decryption"
git -C "$STATE/gitwork" push --quiet "$STATE/repo.git" main
flux reconcile kustomization cluster-apps --with-source --timeout=10m
test "$(kubectl get secret e2e-sops --namespace default \
    --output jsonpath='{.data.value}' | base64 --decode)" = "flux-decrypted"

echo "==> asserting pod networking and DNS"
CONTROLPLANE_NODE="$(kubectl get nodes --output json | jq -r \
    '.items[] | select(.metadata.labels["node-role.kubernetes.io/control-plane"] != null) | .metadata.name' | head -1)"
WORKER_NODE="$(kubectl get nodes --output json | jq -r \
    '.items[] | select(.metadata.labels["node-role.kubernetes.io/control-plane"] == null) | .metadata.name' | head -1)"
kubectl apply --filename - <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: e2e-network-server
  namespace: default
  labels:
    app: e2e-network-server
spec:
  nodeName: $WORKER_NODE
  containers:
    - name: server
      image: registry.k8s.io/e2e-test-images/agnhost:2.63.0
      args: ["netexec", "--http-port=8080"]
      ports:
        - name: http
          containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: e2e-network-server
  namespace: default
spec:
  selector:
    app: e2e-network-server
  ports:
    - name: http
      port: 8080
      targetPort: http
---
apiVersion: v1
kind: Pod
metadata:
  name: e2e-network-client
  namespace: default
spec:
  nodeName: $CONTROLPLANE_NODE
  containers:
    - name: client
      image: registry.k8s.io/e2e-test-images/agnhost:2.63.0
      args: ["pause"]
EOF
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
kubectl apply --filename - <<EOF
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: e2e-deny-server
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: e2e-network-server
  policyTypes: ["Ingress"]
EOF
deadline=$((SECONDS + 60))
while kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=2s "$SERVER_IP:8080" &>/dev/null; do
    if (( SECONDS >= deadline )); then
        just log fatal "NetworkPolicy did not block pod traffic"
    fi
    sleep 2
done
kubectl delete networkpolicy e2e-deny-server --namespace default
deadline=$((SECONDS + 60))
until kubectl exec --namespace default e2e-network-client -- \
    /agnhost connect --timeout=2s "$SERVER_IP:8080" &>/dev/null; do
    if (( SECONDS >= deadline )); then
        just log fatal "Pod traffic did not recover after removing NetworkPolicy"
    fi
    sleep 2
done

kubectl get nodes --output wide
kubectl get kustomizations,helmreleases --all-namespaces
echo "==> e2e bootstrap succeeded"
