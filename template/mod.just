set quiet
set default-list
set default-script
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']
set working-directory := '..'

bootstrap_dir := justfile_dir() + '/bootstrap'
kubernetes_dir := justfile_dir() + '/kubernetes'
talos_dir := justfile_dir() + '/talos'
private_dir := justfile_dir() + '/.private'

template_dir := justfile_dir() + '/template'
template_resources := template_dir + '/resources'
makejinja_config := justfile_dir() + '/makejinja.toml'

config_file := justfile_dir() + '/cluster.toml'
sample_config_file := justfile_dir() + '/cluster.sample.toml'
validate_script := template_dir + '/scripts/validate.py'
deploy_key := justfile_dir() + '/deploy.key'
webhook_token_file := justfile_dir() + '/flux-webhook-token.txt'
cloudflare_tunnel := justfile_dir() + '/cloudflare-tunnel.json'

[doc('Render and validate configuration files')]
[group('template')]
configure: render encrypt-secrets validate-kubernetes validate-talos

[doc('Check that all prerequisite files exist and cluster.toml validates against the schema')]
[group('template')]
[no-exit-message]
doctor:
    rc=0
    just log info "just version" version "{{ just_version() }}"
    just template doctor-check "cluster.toml"           "{{ config_file }}"           || rc=1
    just template doctor-check "cluster.sample.toml"    "{{ sample_config_file }}"    || rc=1
    config_json="$(just template config-json 2>/dev/null || true)"
    if [ "$(jq -r '.ingress.mode' <<< "$config_json" 2>/dev/null)" = "cloudflare-tunnel" ]; then
        just template doctor-check "cloudflare-tunnel.json" "{{ cloudflare_tunnel }}" || rc=1
    fi
    just template doctor-check "age.key"                "$SOPS_AGE_KEY_FILE"          || rc=1
    just template doctor-check "deploy.key"             "{{ deploy_key }}"            || rc=1
    just template doctor-check "flux-webhook-token.txt" "{{ webhook_token_file }}"    || rc=1
    just template doctor-check "template/"              "{{ template_dir }}"          || rc=1
    just template doctor-check "makejinja.toml"         "{{ makejinja_config }}"      || rc=1
    just template doctor-check "validate.py"            "{{ validate_script }}"       || rc=1
    if [ -f "{{ config_file }}" ] && [ -f "{{ validate_script }}" ]; then
        if [ -n "$config_json" ]; then
            just log info "ok" check schema
        else
            just log error "fail" check schema
            just log info "diagnose with: uv run --locked {{ validate_script }} {{ config_file }}"
            rc=1
        fi
    fi
    [ "$rc" = 0 ] && just log info "all good"
    exit "$rc"

[doc('Initialize configuration files (cluster.toml, age key, deploy key, webhook token)')]
[group('template')]
init:
    [ -f "{{ config_file }}" ]        || cp "{{ sample_config_file }}" "{{ config_file }}"
    [ -f "$SOPS_AGE_KEY_FILE" ]       || age-keygen -pq --output "$SOPS_AGE_KEY_FILE"
    [ -f "{{ deploy_key }}" ]         || ssh-keygen -t ed25519 -C "deploy-key" -f "{{ deploy_key }}" -q -P ""
    [ -f "{{ webhook_token_file }}" ] || openssl rand -hex 16 > "{{ webhook_token_file }}"

[confirm("Remove all templated files and directories — continue? [y/N]")]
[doc('Remove rendered files (bootstrap/, kubernetes/, talos/, .sops.yaml)')]
[group('template')]
reset:
    rm -rf "{{ bootstrap_dir }}" "{{ kubernetes_dir }}" "{{ talos_dir }}" "{{ justfile_dir() }}/.sops.yaml"

# tidy-archive moves template/ (this module's source) away, so it runs as a
# subsequent dependency: the tidy script itself must spawn while the module
# directory still exists.
[confirm("All template related config will be archived — continue? [y/N]")]
[doc('Archive all template tooling under .private/<ts>/ (one-way, run after configure works)')]
[group('template')]
tidy: tidy-preconditions tidy-strip && tidy-archive

# Validated, defaulted cluster config as JSON on stdout; fails when the
# config is invalid.
[private]
config-json:
    uv run --quiet --locked "{{ validate_script }}" "{{ config_file }}"

[no-exit-message]
[private]
doctor-check label path:
    if [ -e "{{ path }}" ]; then
        just log info "ok" file "{{ label }}"
    else
        just log error "missing" file "{{ label }}"
        exit 1
    fi

[private]
encrypt-secrets:
    find "{{ bootstrap_dir }}" "{{ kubernetes_dir }}" "{{ talos_dir }}" -type f -name '*.sops.*' -print0 \
        | while IFS= read -r -d '' f; do
            if ! status="$(sops filestatus "$f" | jq -r '.encrypted')"; then
                just log fatal "could not read encryption status" file "$f"
            fi
            case "$status" in
                false) sops encrypt --in-place "$f" ;;
                true)  : ;;
                *)     just log fatal "could not determine encryption status" file "$f" ;;
            esac
        done

[private]
render:
    PYTHONDONTWRITEBYTECODE=1 uv run --locked makejinja

[private]
tidy-archive:
    TIDY_FOLDER="{{ private_dir }}/$(date +%s)"
    mkdir -p "$TIDY_FOLDER"
    rm -rf "{{ justfile_dir() }}/.github/template-tests" "{{ justfile_dir() }}/.github/workflows"/template-*.yaml
    mv \
        "{{ template_dir }}" \
        "{{ makejinja_config }}" \
        "{{ config_file }}" \
        "{{ sample_config_file }}" \
        "{{ justfile_dir() }}/pyproject.toml" \
        "{{ justfile_dir() }}/uv.lock" \
        "$TIDY_FOLDER/"
    rm -rf "{{ justfile_dir() }}/.venv"

[private]
tidy-preconditions:
    test -d "{{ template_dir }}"
    test -d "{{ justfile_dir() }}/.github/template-tests"
    test -f "{{ makejinja_config }}"
    test -f "{{ config_file }}"
    test -f "{{ sample_config_file }}"
    test -f "{{ justfile_dir() }}/pyproject.toml"
    test -f "{{ justfile_dir() }}/uv.lock"
    test -f "{{ justfile_dir() }}/justfile"
    test -f "{{ justfile_dir() }}/.mise/config.toml"
    test -f "{{ justfile_dir() }}/.renovaterc.json5"
    compgen -G "{{ justfile_dir() }}/.github/workflows/template-*.yaml" > /dev/null

[private]
tidy-strip:
    sd '\..\.j2'                          '' "{{ justfile_dir() }}/.renovaterc.json5"
    sd -A '(?ms)^# === template ===$.*'   '' "{{ justfile_dir() }}/justfile"
    sd -A '.*required:template.*\n'       '' "{{ justfile_dir() }}/.mise/config.toml"

# Renders every bootstrap chart with the rendered values, catching chart or
# values drift that dry runs cannot; needs network access to pull charts.
[doc('Render the bootstrap helmfile charts against the rendered values')]
[group('template')]
test-helmfile:
    helmfile --file "{{ bootstrap_dir }}/helmfile/apps.yaml" template --quiet > /dev/null
    just log info "bootstrap charts rendered cleanly"

[private]
validate-kubernetes:
    bash "{{ template_resources }}/kubeconform.sh" "{{ kubernetes_dir }}"

# Rendering needs the secrets bundle; topf generates and sops-encrypts one
# on first run (--confirm=false so it never prompts mid-pipeline).
[private]
[working-directory('talos')]
validate-talos:
    topf render --confirm=false --output "$(mktemp -d)" >/dev/null
    if ! sops filestatus secrets.sops.yaml | jq --exit-status '.encrypted == true' >/dev/null; then
        just log fatal "Talos secrets bundle is not encrypted"
    fi
