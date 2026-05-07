set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[private]
default:
    just talos -l

[doc('Apply Talos config to a node')]
[group('talos')]
apply-node ip mode='auto':
    talosctl --nodes "{{ ip }}" get machineconfig
    talosctl config info
    test -f "$TALOSCONFIG"
    talhelper gencommand apply --node "{{ ip }}" --extra-flags "--mode={{ mode }}" | bash

[doc('Generate Talos configuration')]
[group('talos')]
generate-config:
    test -f "$SOPS_AGE_KEY_FILE"
    talhelper genconfig

[doc('Reset nodes back to maintenance mode (DESTRUCTIVE)')]
[group('talos')]
[confirm("This will destroy your cluster and reset nodes to maintenance mode — continue? [y/N]")]
reset:
    talhelper gencommand reset \
        --extra-flags="--reboot --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --graceful=false --wait=false" | bash

[doc('Upgrade Kubernetes')]
[group('talos')]
upgrade-k8s:
    talosctl config info
    test -f "$TALOSCONFIG"
    talhelper gencommand upgrade-k8s --extra-flags "--to '$(yq '.kubernetesVersion' talenv.yaml)'" | bash

[doc('Upgrade Talos on a single node')]
[group('talos')]
[script]
upgrade-node ip:
    talosctl --nodes "{{ ip }}" get machineconfig
    talosctl config info
    test -f "$TALOSCONFIG"
    image="$(yq ".nodes[] | select(.ipAddress == \"{{ ip }}\") | .talosImageURL" talconfig.yaml)"
    version="$(yq '.talosVersion' talenv.yaml)"
    talhelper gencommand upgrade --node "{{ ip }}" \
        --extra-flags "--image='${image}:${version}' --timeout=10m" | bash
