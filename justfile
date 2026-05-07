set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

[group('bootstrap')]
mod? bootstrap 'bootstrap'

[group('kubernetes')]
mod? kube 'kubernetes'

[group('talos')]
mod? talos 'talos'

[private]
default:
    just -l

[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

# === template ===

[group('template')]
mod template 'template'

[doc('Render and validate configuration files')]
[group('template')]
configure:
    just template configure

[doc('Initialize configuration files (cluster.toml, age key, deploy key, push token)')]
[group('template')]
init:
    just template init
