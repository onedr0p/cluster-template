set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']
set default-list
set default-script

# Day-2 apply/upgrade recipes rely on topf's built-in diff-and-confirm
# prompt; only the destructive reset recipes disable it in favour of just's
# own confirmation.

[doc('Apply Talos config to all nodes (shows a diff and asks first)')]
[group('talos')]
apply:
    topf apply

[arg('mode', pattern='auto|reboot|no-reboot|staged|try')]
[doc('Apply Talos config to a node (shows a diff and asks first)')]
[group('talos')]
apply-node node mode='auto':
    topf apply --nodes-filter "^{{ node }}$" --mode "{{ mode }}"

[doc('Show pending config changes without applying them')]
[group('talos')]
diff:
    topf apply --dry-run

[doc('List all nodes and their current state')]
[group('talos')]
nodes:
    topf nodes

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

[doc('Upgrade Talos on all nodes, one at a time (asks first)')]
[group('talos')]
upgrade:
    topf upgrade

[doc('Upgrade Talos on a single node (asks first)')]
[group('talos')]
upgrade-node node:
    topf upgrade --nodes-filter "^{{ node }}$"
