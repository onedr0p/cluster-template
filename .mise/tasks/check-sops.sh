#!/usr/bin/env bash
#MISE hide=true
#USAGE arg "<file>" var=#true help="SOPS files to check"
set -euo pipefail

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
    fi
done
exit "$rc"
