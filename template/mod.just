set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']
set working-directory := '..'

bootstrap_dir      := justfile_dir() + '/bootstrap'
kubernetes_dir     := justfile_dir() + '/kubernetes'
talos_dir          := justfile_dir() + '/talos'
private_dir        := justfile_dir() + '/.private'

template_dir       := justfile_dir() + '/template'
template_resources := template_dir + '/resources'
makejinja_config   := justfile_dir() + '/makejinja.toml'

config_file        := justfile_dir() + '/cluster.toml'
sample_config_file := justfile_dir() + '/cluster.sample.toml'
schema_file        := template_resources + '/config.schema.cue'
deploy_key         := justfile_dir() + '/github-deploy.key'
push_token_file    := justfile_dir() + '/github-push-token.txt'
cloudflare_tunnel  := justfile_dir() + '/cloudflare-tunnel.json'

[private]
default:
    just template -l

[doc('Render and validate configuration files')]
[group('template')]
configure: configure-preconditions render encrypt-secrets validate-kubernetes validate-talos

[doc('Check that all prerequisite files exist and cluster.toml validates against the schema')]
[group('template')]
[no-exit-message]
[script]
doctor:
    rc=0
    just template doctor-check "cluster.toml"           "{{ config_file }}"           || rc=1
    just template doctor-check "cluster.sample.toml"    "{{ sample_config_file }}"    || rc=1
    just template doctor-check "cloudflare-tunnel.json" "{{ cloudflare_tunnel }}"     || rc=1
    just template doctor-check "age.key"                "$SOPS_AGE_KEY_FILE"          || rc=1
    just template doctor-check "github-deploy.key"      "{{ deploy_key }}"            || rc=1
    just template doctor-check "github-push-token.txt"  "{{ push_token_file }}"       || rc=1
    just template doctor-check "template/"              "{{ template_dir }}"          || rc=1
    just template doctor-check "makejinja.toml"         "{{ makejinja_config }}"      || rc=1
    just template doctor-check "config.schema.cue"      "{{ schema_file }}"           || rc=1
    if [ -f "{{ config_file }}" ] && [ -f "{{ schema_file }}" ]; then
        if cue export "{{ config_file }}" "{{ schema_file }}" --out yaml >/dev/null 2>&1; then
            just log info "ok" check schema
        else
            just log error "fail" check schema
            just log info "diagnose with: cue export {{ config_file }} {{ schema_file }}"
            rc=1
        fi
    fi
    [ "$rc" = 0 ] && just log info "all good"
    exit "$rc"

[doc('Initialize configuration files (cluster.toml, age key, deploy key, push token)')]
[group('template')]
init:
    [ -f "{{ config_file }}" ]     || cp "{{ sample_config_file }}" "{{ config_file }}"
    [ -f "$SOPS_AGE_KEY_FILE" ]    || age-keygen --output "$SOPS_AGE_KEY_FILE"
    [ -f "{{ deploy_key }}" ]      || ssh-keygen -t ed25519 -C "deploy-key" -f "{{ deploy_key }}" -q -P ""
    [ -f "{{ push_token_file }}" ] || openssl rand -hex 16 > "{{ push_token_file }}"

[doc('Remove rendered files (bootstrap/, kubernetes/, talos/, .sops.yaml)')]
[group('template')]
[confirm("Remove all templated files and directories — continue? [y/N]")]
reset:
    rm -rf "{{ bootstrap_dir }}" "{{ kubernetes_dir }}" "{{ talos_dir }}" "{{ justfile_dir() }}/.sops.yaml"

[doc('Archive all template tooling under .private/<ts>/ (one-way, run after configure works)')]
[group('template')]
[confirm("All template related config will be archived — continue? [y/N]")]
tidy: tidy-preconditions tidy-strip tidy-archive

[private]
configure-preconditions:
    test -f "{{ cloudflare_tunnel }}" || { just log error "cloudflare-tunnel.json not found — see README"; exit 1; }

[private]
[no-exit-message]
[script]
doctor-check label path:
    if [ -e "{{ path }}" ]; then
        just log info "ok" file "{{ label }}"
    else
        just log error "missing" file "{{ label }}"
        exit 1
    fi

[private]
[script]
encrypt-secrets:
    find "{{ bootstrap_dir }}" "{{ kubernetes_dir }}" "{{ talos_dir }}" -type f -name '*.sops.*' -print0 \
        | while IFS= read -r -d '' f; do
            if [ "$(sops filestatus "$f" | jq '.encrypted')" = "false" ]; then
                sops --encrypt --in-place "$f"
            fi
        done

[private]
render:
    test -f "{{ schema_file }}"
    test -f "{{ template_dir }}/scripts/plugin.py"
    test -f "{{ makejinja_config }}"
    PYTHONDONTWRITEBYTECODE=1 makejinja

[private]
[script]
tidy-archive:
    TIDY_FOLDER="{{ private_dir }}/$(date +%s)"
    mkdir -p "$TIDY_FOLDER"
    rm -rf "{{ justfile_dir() }}/.github/tests" "{{ justfile_dir() }}/.github/workflows/e2e.yaml" "{{ justfile_dir() }}/.github/workflows/release.yaml"
    mv "{{ template_dir }}"         "$TIDY_FOLDER/template"
    mv "{{ makejinja_config }}"     "$TIDY_FOLDER/makejinja.toml"
    mv "{{ config_file }}"          "$TIDY_FOLDER/cluster.toml"
    mv "{{ sample_config_file }}"   "$TIDY_FOLDER/cluster.sample.toml"
    mv "{{ justfile_dir() }}/.venv" "$TIDY_FOLDER/.venv"

[private]
tidy-preconditions:
    test -d "{{ template_dir }}"
    test -f "{{ makejinja_config }}"
    test -f "{{ justfile_dir() }}/.renovaterc.json5"

[private]
tidy-strip:
    sd '\..\.j2'                       '' "{{ justfile_dir() }}/.renovaterc.json5"
    sd '(?ms)^# === template ===$.*'   '' "{{ justfile_dir() }}/justfile"
    sd '.*required:template.*\n'       '' "{{ justfile_dir() }}/.mise.toml"

[private]
validate-kubernetes:
    test -f "{{ template_resources }}/kubeconform.sh"
    bash "{{ template_resources }}/kubeconform.sh" "{{ kubernetes_dir }}"

[private]
[working-directory('talos')]
validate-talos:
    test -f talconfig.yaml
    talhelper validate talconfig talconfig.yaml
