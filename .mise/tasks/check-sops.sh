#!/usr/bin/env bash
#MISE hide=true
#USAGE arg "<file>" var=#true help="SOPS files to check"
set -euo pipefail

# Lists the values sops should have encrypted but are plain text, e.g. a key
# added to an encrypted file without sops. Each document's sops metadata says
# which values are in scope: those under a key matching encrypted_regex, or
# every value outside a key ending in unencrypted_suffix. sops leaves empty
# strings and nulls as they are. A document without metadata is listed by its
# index.
read -r -d '' plaintext <<'EOF' || true
select(tag == "!!map" and (has("sops") | not)) | "document " + (document_index | tostring)
,
select(tag == "!!map" and has("sops")) | .sops as $sops | del(.sops)
| (
    if $sops.encrypted_regex then
      .. | select(key | tag == "!!str") | select(key | test($sops.encrypted_regex))
    else
      del(.. | select(key | tag == "!!str") | select(key | test(($sops.unencrypted_suffix // "_unencrypted") + "$")))
    end
  )
| ..
| select(tag != "!!map" and tag != "!!seq" and tag != "!!null" and . != "")
| select(if tag == "!!str" then (test("^ENC\[") | not) else true end)
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
    elif [[ "$f" =~ \.(ya?ml|json)$ ]]; then
        if ! leaks="$(yq --no-doc --unwrapScalar "$plaintext" "$f")"; then
            mise run //:log error "Failed to parse file" file "$f"
            rc=1
        elif [[ -n "$leaks" ]]; then
            mise run //:log error "File has plain text values, re-encrypt it with sops" file "$f" values "${leaks//$'\n'/, }"
            rc=1
        fi
    fi
done
exit "$rc"
