set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[private]
default:
    just talos -l

[doc('Apply Talos config to a node')]
[group('talos')]
apply-node ip mode='auto':
    talhelper gencommand apply --node "{{ ip }}" --extra-flags "--mode={{ mode }}" | bash

[doc('Generate Talos configuration')]
[group('talos')]
generate-config:
    talhelper genconfig

[doc('Reset all nodes back to maintenance mode (DESTRUCTIVE)')]
[group('talos')]
[confirm("This will destroy your cluster and reset all nodes to maintenance mode — continue? [y/N]")]
reset:
    talhelper gencommand reset \
        --extra-flags="--reboot --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --graceful=false --wait=false" | bash

[doc('Reset a single node back to maintenance mode (DESTRUCTIVE)')]
[group('talos')]
[confirm("This will reset the specified node to maintenance mode — continue? [y/N]")]
reset-node ip:
    talhelper gencommand reset --node "{{ ip }}" \
        --extra-flags="--reboot --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --graceful=false --wait=false" | bash

[doc('Upgrade Kubernetes')]
[group('talos')]
upgrade-k8s:
    talhelper gencommand upgrade-k8s --extra-flags "--to '$(yq '.kubernetesVersion' talenv.yaml)'" | bash

[doc('Upgrade Talos on a single node')]
[group('talos')]
upgrade-node ip:
    talhelper gencommand upgrade --node "{{ ip }}" --extra-flags "--timeout=10m" | bash
