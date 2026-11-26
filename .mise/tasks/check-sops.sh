#!/usr/bin/env bash
#MISE hide=true
#USAGE arg "<file>" var=#true help="SOPS files to check"
set -euo pipefail

# Lists values under the keys matched by encrypted_regex (all keys when unset)
# that are not ENC[...], e.g. a key added to an encrypted file without sops.
# Other sops selection options are not used by this repo, so not handled.
read -r -d '' plaintext <<'EOF' || true
(.sops.encrypted_regex // "") as $re
| del(.sops)
| with_entries(select(.key | test($re)))
| .. | select(kind == "scalar" and tag != "!!null" and . != "")
| select(tag != "!!str" or (test("^ENC\[") | not))
| path | join(".")
EOF

# sops metadata alone does not mean the values are encrypted: a file without
# data/stringData gets metadata and a MAC but no other ENC[] value.
rc=0
for f in "$@"; do
    if ! sops filestatus "$f" 2>/dev/null | jq --exit-status '.encrypted == true' >/dev/null; then
        mise run //:log error "File is not encrypted" file "$f"
        rc=1
    elif ! awk '/ENC\[/ && !/^[[:space:]]*"?(sops_)?mac"?[[:space:]]*[:=]/ { found = 1; exit } END { exit !found }' < "$f"; then
        mise run //:log error "File has no encrypted values, only data and stringData are encrypted" file "$f"
        rc=1
    elif [[ "$f" == *.y*ml ]] && leaks="$(yq --no-doc "$plaintext" "$f")" && [[ -n "$leaks" ]]; then
        mise run //:log error "File has plain text values, add them with sops edit instead" file "$f" values "${leaks//$'\n'/, }"
        rc=1
    fi
done
exit "$rc"
