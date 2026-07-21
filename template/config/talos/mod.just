set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']
set default-list

[doc('Apply Talos config to a node')]
[group('talos')]
apply-node node mode='auto':
    topf apply --nodes-filter "^{{ node }}$" --mode "{{ mode }}" --confirm=false

[doc('Render Talos machine configs to ./rendered')]
[group('talos')]
render:
    topf render --output ./rendered

[confirm("This will destroy your cluster and reset all nodes to maintenance mode — continue? [y/N]")]
[doc('Reset all nodes back to maintenance mode (DESTRUCTIVE)')]
[group('talos')]
reset:
    topf reset --confirm=false

[confirm("This will reset node " + node + " to maintenance mode — continue? [y/N]")]
[doc('Reset a single node back to maintenance mode (DESTRUCTIVE)')]
[group('talos')]
reset-node node:
    topf reset --nodes-filter "^{{ node }}$" --confirm=false

# topf intentionally does not manage Kubernetes upgrades
[doc('Upgrade Kubernetes')]
[group('talos')]
upgrade-k8s:
    talosctl --nodes "$(yq '[.nodes[] | select(.role == "control-plane")][0].ip' topf.yaml)" \
        upgrade-k8s --to "$(yq '.kubernetesVersion' topf.yaml)"

[doc('Upgrade Talos on a single node')]
[group('talos')]
upgrade-node node:
    topf upgrade --nodes-filter "^{{ node }}$" --confirm=false
